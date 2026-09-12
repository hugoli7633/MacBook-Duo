import SwiftUI
import AppKit

@main
struct HingeGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWindow?
    private var model: AppModel?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var globalController: GlobalDesktopController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        model.globalStatus = "正在检查屏幕录制权限…"
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let contentSize = NSSize(width: min(680, screen.visibleFrame.width - 80),
                                 height: min(820, screen.visibleFrame.height - 80))
        let window = DesktopWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        if let iconURL = Bundle.main.url(forResource: "MacBookDuo", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.contentMinSize = NSSize(width: 660, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(model: model))
        self.window = window
        let globalController = GlobalDesktopController(model: model, setupWindow: window)
        self.globalController = globalController
        model.startGlobal = { [weak globalController] in globalController?.start() }
        model.previewGlobal = { [weak globalController] in globalController?.preview() }
        model.stopGlobal = { [weak globalController] in globalController?.disable() }
        model.hideControls = { [weak window] in window?.orderOut(nil) }
        NSApp.presentationOptions = []
        NSApp.setActivationPolicy(.accessory)
        window.center()
        let showSettings = ProcessInfo.processInfo.arguments.contains("--show-settings")
        if !model.backgroundEnabled || showSettings { globalController.showSetup() }
        Task { @MainActor in
            model.globalStatus = await ScreenCapturePermissionPreparation.prepare()
            model.permissionsPreparing = false
            globalController.restoreAtLaunch(keepingControlsVisible: showSettings)
            if showSettings { model.desktopPreview.refresh() }
        }
        // Handle before AppKit's default Command-H (which hides the whole app).
        // Restricted to this window so file dialogs retain their own shortcuts.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, let model = self.model else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "h" {
                if model.page == .test && !event.isARepeat { model.controlsHidden.toggle() }
                return nil
            }
            guard model.page == .test else { return event }
            if modifiers == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "k":
                    if !event.isARepeat { model.saveOpenAngle() }
                    return nil
                case "b":
                    if !event.isARepeat { model.showOriginal.toggle() }
                    return nil
                default: break
                }
            }
            if event.keyCode == 53 {
                model.controlsHidden = false
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.globalController?.screenConfigurationChanged() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.loginItem.refresh()
    }

    @MainActor @objc private func openSettings() {
        globalController?.showSetup()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "打开设置", action: #selector(openSettings), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        globalController?.showSetup()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
