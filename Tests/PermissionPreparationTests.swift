import Foundation

@main
struct PermissionPreparationTests {
    static func main() {
        typealias Preparation = ScreenCapturePermissionPreparation
        assert(Preparation.statusMessage(hasAccess: true) == "屏幕录制权限已就绪")
        assert(Preparation.statusMessage(hasAccess: false).contains("需要屏幕录制权限"))
        print("PASS: permission status for granted and missing access")
    }
}
