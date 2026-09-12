import AppKit

enum StatusIcon {
    static func make(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        let image = NSImage(size: size, flipped: false) { rect in
            symbol?.draw(in: rect)
            (active ? NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1) : NSColor.white).setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        // Bake the symbol into colored pixels instead of handing AppKit a symbol.
        var bounds = NSRect(origin: .zero, size: size)
        guard let pixels = image.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else {
            image.isTemplate = false
            return image
        }
        let rendered = NSImage(cgImage: pixels, size: size)
        rendered.isTemplate = false
        return rendered
    }
}
