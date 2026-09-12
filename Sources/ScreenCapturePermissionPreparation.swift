import CoreGraphics

/// Startup only checks permission. Never erase an existing grant or prompt at login.
enum ScreenCapturePermissionPreparation {
    static func statusMessage(hasAccess: Bool) -> String {
        hasAccess ? "屏幕录制权限已就绪" : "需要屏幕录制权限，请点击启用并按系统提示允许"
    }

    static func prepare() async -> String {
        statusMessage(hasAccess: CGPreflightScreenCaptureAccess())
    }
}
