import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    private let defaults: UserDefaults
    enum Page {
        case setup
        case test
    }

    @Published var page: Page = .setup
    @Published var desktopImage: NSImage?
    @Published var importedFileName = ""
    @Published var useSensor = true
    @Published var simulatedAngle = 105.0
    @Published var controlsHidden = false
    @Published var showOriginal = false
    @Published var calibrationMessage = ""
    @Published var openAngle = 120.0
    @Published var blurStartAngle = 90.0 {
        didSet { defaults.set(blurStartAngle, forKey: "blurStartAngle") }
    }
    @Published var globalStatus = "实时桌面模式需要屏幕录制权限"
    @Published var globalRunning = false
    @Published var permissionsPreparing = true
    @Published var backgroundEnabled = false {
        didSet { defaults.set(backgroundEnabled, forKey: "backgroundEnabled") }
    }
    let loginItem = LoginItemController()
    let desktopPreview = DesktopPreviewCapture()
    @Published var restarting = false

    func restartAfterPermission() {
        guard !restarting else { return }
        restarting = true
        do { try AppRestarter.restart() }
        catch {
            restarting = false
            globalStatus = "重启失败：\(error.localizedDescription)"
        }
    }
    var startGlobal: (() -> Void)?
    var previewGlobal: (() -> Void)?
    var stopGlobal: (() -> Void)?
    var hideControls: (() -> Void)?

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    var currentAngle: Double { useSensor && sensor.isAvailable ? sensor.angle : simulatedAngle }

    func saveOpenAngle() {
        let value = currentAngle
        guard value.isFinite, value >= 1, value <= 180 else {
            calibrationMessage = "请先打开屏幕，再保存展开终点"
            controlsHidden = false
            return
        }
        openAngle = value
        blurStartAngle = min(blurStartAngle, value)
        defaults.set(value, forKey: "calibratedOpenAngle")
        calibrationMessage = "已保存展开终点"
    }

    let sensor = LidAngleSensor()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backgroundEnabled = defaults.bool(forKey: "backgroundEnabled")
        let saved = defaults.object(forKey: "calibratedOpenAngle") as? Double
            ?? UserDefaults(suiteName: "studio.prototype.HingeGlass")?.double(forKey: "calibratedOpenAngle") ?? 120
        if saved >= 1 && saved <= 180 { openAngle = saved }
        let savedBlurStart = defaults.object(forKey: "blurStartAngle") as? Double ?? 90
        blurStartAngle = min(openAngle, savedBlurStart.isFinite ? max(1, savedBlurStart) : 90)
        sensor.start()
    }

    func importScreenshot() {
        let panel = NSOpenPanel()
        panel.title = "选择桌面截图"
        panel.message = "请选择一张完整的桌面截图，用作玻璃层下方的内容。"
        panel.prompt = "导入截图"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }

        desktopImage = image
        importedFileName = url.lastPathComponent
    }

    func startTest() {
        guard desktopImage != nil else { return }
        controlsHidden = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            page = .test
        }
    }

    func returnToSetup() {
        controlsHidden = false
        withAnimation(.easeInOut(duration: 0.3)) {
            page = .setup
        }
    }

}
