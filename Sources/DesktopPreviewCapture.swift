import AppKit
import ScreenCaptureKit

@MainActor
final class DesktopPreviewCapture: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var loading = false
    @Published private(set) var message = "允许屏幕录制后显示当前桌面"

    func refresh() {
        guard !loading else { return }
        guard CGPreflightScreenCaptureAccess() else {
            image = nil
            message = "允许屏幕录制后显示当前桌面"
            return
        }
        loading = true
        Task { @MainActor in
            defer { loading = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? content.displays.first,
                      let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
                    throw NSError(domain: "MacBookDuo.Preview", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "无法获取桌面预览"])
                }
                let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 1440
                config.height = Int(Double(display.height) / Double(display.width) * 1440)
                config.showsCursor = false
                config.capturesAudio = false
                let screenshot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                image = NSImage(cgImage: screenshot, size: NSSize(width: screenshot.width, height: screenshot.height))
                message = "当前桌面快照 · 仅在本机预览"
            } catch {
                message = "桌面预览不可用，请允许录屏后重启应用"
            }
        }
    }
}
