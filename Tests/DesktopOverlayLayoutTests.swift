import CoreGraphics

@main
struct DesktopOverlayLayoutTests {
    static func main() {
        for origin in [CGPoint.zero, CGPoint(x: -1500, y: -900)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1500, height: 900))
            let layout = DesktopOverlayLayout(screenFrame: screen, menuBarHeight: 38)
            assert(layout.windowFrame.maxY == screen.maxY - 38)
            assert(layout.windowFrame.minY == screen.minY)
            assert(layout.captureRect.origin == CGPoint(x: 0, y: 38))
            assert(layout.captureRect.maxY == screen.height)
            assert(layout.captureRect.size == layout.windowFrame.size)
        }
        print("PASS: menu bar exclusion and matching capture coordinates")
    }
}
