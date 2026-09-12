import CoreGraphics

struct DesktopOverlayLayout {
    let windowFrame: CGRect
    let captureRect: CGRect

    init(screenFrame: CGRect, menuBarHeight: CGFloat) {
        let inset = min(max(0, menuBarHeight), max(0, screenFrame.height - 1))
        // AppKit uses bottom-left origins; ScreenCaptureKit uses top-left origins.
        windowFrame = CGRect(x: screenFrame.minX, y: screenFrame.minY,
                             width: screenFrame.width, height: screenFrame.height - inset)
        captureRect = CGRect(x: 0, y: inset, width: screenFrame.width,
                             height: screenFrame.height - inset)
    }
}
