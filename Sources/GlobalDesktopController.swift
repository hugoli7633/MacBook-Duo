import AppKit
import ScreenCaptureKit
import Carbon
import CoreMedia

// Capture and render are local only. No recordings or network output.
@MainActor
final class GlobalDesktopController: NSObject, @preconcurrency SCStreamOutput, SCStreamDelegate, NSMenuDelegate {
    private let model: AppModel
    private weak var setupWindow: NSWindow?
    private var overlay: NSWindow?
    private var renderer: GlassMetalView?
    private var stream: SCStream?
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private let activeIcon = StatusIcon.make(active: true)
    private let inactiveIcon = StatusIcon.make(active: false)
    private var iconActive: Bool?
    private var toggleItem: NSMenuItem?
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var generation = 0
    private var starting = false
    private var startedAt = Date()
    // Keep only the newest frame while clear; upload it when the effect returns.
    private var pendingBuffer: CVPixelBuffer?
    private var receivedFrame = false
    private var requestedVisible = false
    private var previewUntil = Date.distantPast
    private var previewRequested = false
    private var frameCount = 0
    private var capturedDisplayID: CGDirectDisplayID?
    private var capturedScreenFrame: NSRect?
    private var statusLine: NSMenuItem!
    private var statusTick = 0
    private var menuOpen = false
    private var observers: [NSObjectProtocol] = []
    private var resumeWanted = false
    private var sleepReasons = Set<String>()
    private var recoveryTimer: Timer?
    private var recoveryFailures = 0
    private var nextRecoveryAttempt = Date.distantPast
    // The setup window is hidden during capture. After wake, on-screen content
    // may omit our process, but the SCApplication from this process remains valid.
    private var captureApplication: SCRunningApplication?

    init(model: AppModel, setupWindow: NSWindow) {
        self.model = model
        self.setupWindow = setupWindow
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIndicator(active: false, status: "未启用")
        statusItem.button?.setAccessibilityLabel("MacBook Duo")
        let menu = NSMenu()
        menu.delegate = self
        statusLine = NSMenuItem(title: "尚未启动", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        for (title, action) in [
            ("测试实时效果（8秒）", #selector(preview)),
            ("开启 / 停止全局效果   ⌘⇧G", #selector(toggle)),
            ("保存当前铰链终点   ⌘⇧K", #selector(calibrate)),
            ("打开控制界面", #selector(showSetup)),
            ("紧急停止并打开控制界面   ⌘⇧Esc", #selector(emergencyStop)),
            ("退出 MacBook Duo", #selector(quit))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if action == #selector(toggle) { toggleItem = item }
            menu.addItem(item)
        }
        statusItem.menu = menu
        registerKeys()
        for (name, key) in [(NSWorkspace.willSleepNotification, "system"),
                            (NSWorkspace.screensDidSleepNotification, "display"),
                            (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sleepReasons.insert(key)
                        self?.suspend(reason: "已暂停，开盖唤醒后自动恢复")
                    }
                })
        }
        for (name, key) in [(NSWorkspace.didWakeNotification, "system"),
                            (NSWorkspace.screensDidWakeNotification, "display"),
                            (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sleepReasons.remove(key)
                        self?.recoverIfReady()
                    }
                })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Retain the texture across Space changes; sleep/session guards
            // prevent the desktop overlay from being drawn over a locked session.
            MainActor.assumeIsolated {
                self?.overlay?.orderOut(nil)
                self?.startedAt = Date()
            }
        })
    }

    @objc func preview() {
        previewRequested = true
        if stream != nil {
            setupWindow?.orderOut(nil)
            previewUntil = Date().addingTimeInterval(8)
        } else { start() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        toggleItem?.title = model.globalRunning ? "停止实时效果   ⌘⇧G" : "启用实时效果   ⌘⇧G"
        toggleItem?.state = model.globalRunning ? .on : .off
        if stream != nil { refreshStatusLine() }
    }

    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func refreshStatusLine() {
        let state = overlay?.isVisible == true ? "效果显示中" : (setupWindow?.isVisible == true ? "调整设置中" : "已启用 · 清晰待机")
        statusLine.title = "\(state) · 当前 \(Int(model.sensor.angle))° · 开始模糊 \(Int(model.blurStartAngle))° · 已捕获 \(frameCount) 帧"
    }

    private func updateIndicator(active: Bool, status: String) {
        if iconActive != active {
            statusItem.button?.image = active ? activeIcon : inactiveIcon
            iconActive = active
        }
        let description = "MacBook Duo · \(status)"
        if statusItem.button?.toolTip != description {
            statusItem.button?.toolTip = description
            statusItem.button?.setAccessibilityLabel(description)
        }
    }

    func restoreAtLaunch(keepingControlsVisible: Bool = false) {
        guard model.backgroundEnabled else { return }
        guard CGPreflightScreenCaptureAccess() else {
            model.globalStatus = "录屏权限未就绪，请从菜单打开控制界面重新启用"
            statusLine.title = model.globalStatus
            updateIndicator(active: false, status: model.globalStatus)
            return
        }
        start(automatically: true, keepingControlsVisible: keepingControlsVisible)
    }

    @objc func disable() {
        model.backgroundEnabled = false
        stop(reason: "实时效果已停止")
    }

    @objc private func emergencyStop() {
        disable()
        showSetup()
    }

    @objc private func toggle() {
        if stream != nil || starting || resumeWanted { disable() } else { start() }
    }
    @objc private func calibrate() {
        guard model.sensor.isAvailable else { return }
        // Global mode always calibrates the real hinge, never a preview slider.
        model.useSensor = true
        model.saveOpenAngle()
    }
    @objc func showSetup() {
        // Keep the enabled state while editing. Closing this window resumes display.
        if overlay?.isVisible == true { overlay?.orderOut(nil) }
        renderer?.isPaused = true
        requestedVisible = false
        model.returnToSetup()
        model.loginItem.refresh()
        updateIndicator(active: false, status: model.globalRunning ? "调整设置中，关闭窗口后继续" : model.globalStatus)
        NSApp.presentationOptions = []
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() {
        // Quitting this session does not change the user's saved enabled preference.
        stop(reason: "已停止")
        NSApp.terminate(nil)
    }

    func start(automatically: Bool = false, keepingControlsVisible: Bool = false) {
        guard !model.permissionsPreparing else { return }
        guard !starting && stream == nil else { return }
        if automatically && !CGPreflightScreenCaptureAccess() {
            stop(reason: "录屏权限未就绪，请从菜单打开控制界面重新启用")
            return
        }
        guard !hotKeys.isEmpty else {
            model.globalStatus = "紧急停止快捷键注册失败，未启用覆盖层"
            updateIndicator(active: false, status: model.globalStatus)
            statusLine.title = model.globalStatus
            return
        }
        guard model.sensor.isAvailable else {
            model.globalStatus = "没有可用的真实铰链传感器，请使用截图测试模式"
            updateIndicator(active: false, status: model.globalStatus)
            statusLine.title = model.globalStatus
            return
        }
        if !automatically {
            recoveryFailures = 0
            nextRecoveryAttempt = .distantPast
        }
        resumeWanted = true
        guard sleepReasons.isEmpty else {
            suspend(reason: "等待屏幕唤醒后自动恢复")
            return
        }
        starting = true
        generation += 1
        let token = generation
        model.globalStatus = "正在请求桌面捕获；如出现系统提示，请允许屏幕录制"
        updateIndicator(active: false, status: "正在启动")
        Task { @MainActor in
            do {
                // Include offscreen windows so a menu-only launch can exclude itself.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard token == generation else { return }
                // Target the built-in panel. External displays aren't hinge-driven.
                guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
                      let screen = NSScreen.screens.first(where: {
                          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
                      }) else { throw GlobalError.noInternalDisplay }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                if let application = content.applications.first(where: { $0.processID == ownPID }) {
                    captureApplication = application
                }
                guard let application = captureApplication, application.processID == ownPID else {
                    throw GlobalError.cannotExcludeSelf
                }
                let excluded = [application]
                let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
                let config = SCStreamConfiguration()
                let layout = overlayLayout(for: screen)
                // Logical resolution for prototype power budget; native panel output.
                config.sourceRect = layout.captureRect
                config.width = Int(layout.captureRect.width)
                config.height = Int(layout.captureRect.height)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                let renderer = self.renderer ?? GlassMetalView()
                guard renderer.device != nil else { throw GlobalError.noGPU }
                let overlay = (self.overlay as? NSPanel) ?? NSPanel(contentRect: layout.windowFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                overlay.hidesOnDeactivate = false
                overlay.becomesKeyOnlyIfNeeded = true
                overlay.isReleasedWhenClosed = false
                overlay.backgroundColor = .black
                overlay.hasShadow = false
                overlay.ignoresMouseEvents = true
                // A nonactivating panel may join other applications' native
                // fullscreen spaces without taking their keyboard focus.
                // Leave the real menu bar exposed so status colors remain visible.
                // Keep the desktop composite below screen saver/security surfaces.
                // Mouse events still pass through; global emergency keys remain.
                overlay.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
                overlay.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications,
                                              .fullScreenAuxiliary, .stationary, .ignoresCycle]
                overlay.contentView = renderer
                overlay.setFrame(layout.windowFrame, display: false)
                self.renderer = renderer
                self.overlay = overlay
                capturedDisplayID = display.displayID
                capturedScreenFrame = screen.frame
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                self.stream = stream
                frameCount = 0
                if !keepingControlsVisible { setupWindow?.orderOut(nil) }
                NSApp.presentationOptions = []
                startedAt = Date()
                pendingBuffer = nil
                if !automatically { receivedFrame = false }
                try await stream.startCapture()
                guard token == generation else {
                    try? await stream.stopCapture()
                    return
                }
                starting = false
                if !sleepReasons.isEmpty {
                    suspend(reason: "保留画面，等待开盖继续")
                    return
                }
                recoveryTimer?.invalidate()
                recoveryTimer = nil
                if previewRequested {
                    previewUntil = Date().addingTimeInterval(8)
                    previewRequested = false
                }
                model.globalRunning = true
                model.backgroundEnabled = true
                model.globalStatus = "实时桌面已启用 · ⌘⇧Esc 停止并恢复设置"
                statusItem.button?.toolTip = model.globalStatus
                NSLog("Global capture started")
                resumeRendering()
            } catch {
                guard token == generation else { return }
                let failedStream = self.stream
                self.stream = nil
                starting = false
                if let failedStream { Task { try? await failedStream.stopCapture() } }
                if automatically && recoveryFailures < 3 {
                    recoveryFailures += 1
                    nextRecoveryAttempt = Date().addingTimeInterval(Double(recoveryFailures))
                    suspend(reason: "唤醒后正在重试（\(recoveryFailures)/3）：\(error.localizedDescription)")
                    return
                }
                stop(reason: "无法启动：\(error.localizedDescription)。请检查系统设置 → 隐私与安全性 → 屏幕录制权限。")
                if !automatically { showSetup() }
            }
        }
    }

    private func suspend(reason: String) {
        guard resumeWanted || stream != nil || starting else { return }
        // Suspension must not destroy the window, GPU textures, or healthy stream.
        timer?.invalidate()
        timer = nil
        renderer?.isPaused = true
        if overlay?.isVisible == true { overlay?.orderOut(nil) }
        updateIndicator(active: false, status: reason)
        model.globalRunning = true
        model.globalStatus = reason
        statusLine?.title = reason
        NSLog("Global suspended (resources retained): %@", reason)
        if recoveryTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverIfReady() }
            }
            recoveryTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func recoverIfReady() {
        guard resumeWanted, sleepReasons.isEmpty, !starting,
              Date() >= nextRecoveryAttempt,
              !model.permissionsPreparing, model.sensor.isAvailable,
              Date().timeIntervalSince(model.sensor.lastSuccessfulUpdate) < 0.5,
              NSScreen.screens.contains(where: {
                  guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
                  return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
              }) else { return }
        if stream != nil {
            recoveryTimer?.invalidate()
            recoveryTimer = nil
            startedAt = Date()
            resumeRendering()
            model.globalStatus = "开盖继续显示 · 窗口与画面已保留"
            NSLog("Global resumed using existing stream and renderer")
            return
        }
        // Wake recovery must never open a fresh permission prompt by itself.
        guard CGPreflightScreenCaptureAccess() else {
            stop(reason: "屏幕录制权限不可用，请手动启用实时效果并允许权限")
            return
        }
        start(automatically: true)
    }

    private func resumeRendering() {
        renderer?.isPaused = false
        timer?.invalidate()
        // Match the 30 Hz sensor; Metal independently smooths motion at 60 Hz.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.timer = timer
        timer.tolerance = 0.003
        RunLoop.main.add(timer, forMode: .common)
        update()
    }

    func stop(reason: String, preserveIntent: Bool = false) {
        if !preserveIntent {
            resumeWanted = false
            recoveryTimer?.invalidate()
            recoveryTimer = nil
        }
        generation += 1
        starting = false
        overlay?.orderOut(nil)
        overlay = nil
        renderer = nil
        pendingBuffer = nil
        capturedDisplayID = nil
        capturedScreenFrame = nil
        timer?.invalidate()
        timer = nil
        let oldStream = stream
        stream = nil
        if let oldStream { Task { try? await oldStream.stopCapture() } }
        receivedFrame = false
        requestedVisible = false
        previewRequested = false
        previewUntil = .distantPast
        model.globalRunning = preserveIntent
        model.globalStatus = reason
        updateIndicator(active: false, status: reason)
        statusLine?.title = reason
        NSLog("Global stopped: %@", reason)
    }

    private func overlayLayout(for screen: NSScreen) -> DesktopOverlayLayout {
        let menuHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top,
                             screen.frame.maxY - screen.visibleFrame.maxY)
        return DesktopOverlayLayout(screenFrame: screen.frame, menuBarHeight: menuHeight)
    }

    func screenConfigurationChanged() {
        // Menu/Dock visibility also posts screen-parameter notifications.
        // Only stop for a real change to the captured display or its full frame.
        guard let id = capturedDisplayID, let overlay else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        if screen == nil || screen!.frame != capturedScreenFrame {
            if let screen {
                overlay.setFrame(overlayLayout(for: screen).windowFrame, display: false)
                let oldStream = stream
                stream = nil
                if let oldStream { Task { try? await oldStream.stopCapture() } }
            }
            suspend(reason: "内建显示器变化，等待恢复实时效果")
        }
    }

    private func update() {
        guard sleepReasons.isEmpty else { return }
        guard let renderer, let overlay else { return }
        if Date().timeIntervalSince(model.sensor.lastSuccessfulUpdate) > 2 {
            suspend(reason: "等待铰链数据恢复后自动继续")
            return
        }
        if !receivedFrame && Date().timeIntervalSince(startedAt) > 8 {
            if recoveryFailures < 3 {
                recoveryFailures += 1
                suspend(reason: "等待唤醒后的桌面画面，正在重新连接")
            } else {
                stop(reason: "桌面捕获超时，已撤掉覆盖层；按 ⌘⇧G 重试")
            }
            return
        }
        // A static desktop may legitimately produce no new complete frames.
        // Keep the last valid texture; explicit stream errors still stop immediately.
        let controlsVisible = setupWindow?.isVisible == true
        let remaining = controlsVisible ? 0 : (Date() < previewUntil ? 0.35 : EffectAngle.progress(angle: model.sensor.angle, onset: model.blurStartAngle))
        renderer.setLiveAngle(remaining * 80)
        // Hysteresis prevents overlay flicker near the calibrated endpoint.
        if remaining > 0.008 { requestedVisible = true }
        if remaining == 0 && renderer.settled { requestedVisible = false }
        if requestedVisible, let buffer = pendingBuffer {
            renderer.receive(buffer)
            pendingBuffer = nil
        }
        if requestedVisible && receivedFrame && renderer.readyForDisplay {
            if !overlay.isVisible { overlay.orderFrontRegardless() }
        } else {
            if overlay.isVisible { overlay.orderOut(nil) }
            renderer.isPaused = true
        }
        updateIndicator(active: overlay.isVisible, status: overlay.isVisible ? "模糊效果生效中" : (controlsVisible ? "调整设置中，关闭窗口后继续" : "已启用 · 清晰待机"))
        statusTick += 1
        if statusTick % 30 == 0 {
            // The frame counter is useful only while the menu is open.
            if menuOpen { refreshStatusLine() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard self.stream === stream, type == .screen, sampleBuffer.isValid else { return }
        guard sleepReasons.isEmpty else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pendingBuffer = buffer
        recoveryFailures = 0
        receivedFrame = true
        frameCount += 1
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.stream = nil
            if recoveryFailures < 3 {
                recoveryFailures += 1
                suspend(reason: "捕获暂时中断，等待恢复：\(error.localizedDescription)")
            } else {
                stop(reason: "捕获恢复失败，请手动重新启用：\(error.localizedDescription)")
            }
        }
    }

    private func registerKeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let controller = Unmanaged<GlobalDesktopController>.fromOpaque(pointer).takeUnretainedValue()
            switch id.id {
            case 1: controller.emergencyStop()
            case 2: controller.toggle()
            case 3: controller.calibrate()
            default: break
            }
            return noErr
        }, 1, &event, pointer, &eventHandler)
        for (id, code) in [(UInt32(1), UInt32(kVK_Escape)), (2, UInt32(kVK_ANSI_G)), (3, UInt32(kVK_ANSI_K))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(code, UInt32(cmdKey | shiftKey),
                EventHotKeyID(signature: 0x48474C53, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotKeys.append(ref) }
            else if id == 1 { break } // Never start without an emergency exit.
        }
    }

    enum GlobalError: LocalizedError {
        case noInternalDisplay, cannotExcludeSelf, noGPU
        var errorDescription: String? {
            switch self {
            case .noInternalDisplay: return "未找到内建显示屏"
            case .cannotExcludeSelf: return "无法排除自身窗口，为避免重复捕获已取消"
            case .noGPU: return "Metal 不可用"
            }
        }
    }
}
