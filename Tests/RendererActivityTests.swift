import AppKit
import MetalKit

@main
struct RendererActivityTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let renderer = GlassMetalView()
        guard renderer.device != nil else { fatalError("Metal device unavailable") }
        let image = NSImage(contentsOfFile: "Assets/MacBookDuo.png")!
        renderer.configure(image: image, tilt: 0, frost: 0.09, distance: 2.4)
        assert(renderer.readyForDisplay, "Shader pipeline and image texture must initialize")
        renderer.isPaused = true
        renderer.setLiveAngle(0)
        assert(renderer.isPaused, "Unchanged settled angle must not wake the GPU")
        renderer.configure(image: image, tilt: 0, frost: 0.09, distance: 2.4)
        assert(renderer.isPaused, "Unchanged SwiftUI updates must not wake the GPU")
        renderer.configure(image: image, tilt: 0, frost: 0.12, distance: 2.4)
        assert(!renderer.isPaused, "Changed blur settings must redraw")
        renderer.isPaused = true
        renderer.setLiveAngle(20)
        assert(!renderer.isPaused, "Hinge motion must resume animation")
        renderer.isPaused = true
        renderer.setLiveAngle(20)
        assert(!renderer.isPaused, "Unsettled motion must be allowed to finish")
        print("PASS: runtime Metal compilation, idle pause, parameter and motion wakeups")
    }
}
