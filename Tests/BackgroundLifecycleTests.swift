import AppKit

@main
struct BackgroundLifecycleTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "studio.prototype.HingeGlass.lifecycle-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        assert(!model.backgroundEnabled)
        model.blurStartAngle = 65
        model.backgroundEnabled = true
        let reopened = AppModel(defaults: UserDefaults(suiteName: suite)!)
        assert(reopened.backgroundEnabled && reopened.blurStartAngle == 65)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = GlobalDesktopController(model: model, setupWindow: window)
        model.globalRunning = true
        controller.showSetup()
        assert(model.globalRunning && model.backgroundEnabled, "Opening settings must preserve enabled intent")
        window.close()
        assert(model.globalRunning && model.backgroundEnabled, "Closing settings must not disable the feature")
        controller.disable()
        assert(!model.globalRunning && !model.backgroundEnabled)
        assert(!AppModel(defaults: UserDefaults(suiteName: suite)!).backgroundEnabled,
               "Explicit stop must remain stopped after relaunch")

        for active in [false, true] {
            let icon = StatusIcon.make(active: active)
            assert(!icon.isTemplate)
            var rect = NSRect(origin: .zero, size: icon.size)
            let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var opaquePixels = 0
            var coloredPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.5 else { continue }
                    opaquePixels += 1
                    let components = [color.redComponent, color.greenComponent, color.blueComponent]
                    if components.max()! - components.min()! > 0.15 { coloredPixels += 1 }
                    if !active { assert(components.min()! > 0.9, "Inactive icon must be white") }
                    if active {
                        assert(color.blueComponent - color.redComponent > 0.4 && color.blueComponent - color.greenComponent > 0.2,
                               "Active icon must be blue: \(components), alpha \(color.alphaComponent)")
                    }
                }
            }
            assert(opaquePixels > 0)
            assert(active ? coloredPixels > 0 : coloredPixels == 0)
        }
        print("PASS: preference restoration, settings open/close, explicit stop, colored/white icons")
    }
}
