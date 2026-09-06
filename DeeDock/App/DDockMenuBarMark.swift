import AppKit

/// Template images for the menu-bar extra. `MenuBarExtra` uses an image's point size, so each
/// style is copied onto a canvas that fits a normal status item.
enum DDockMenuBarMark {
    static func image(for style: MenuBarIconStyle) -> NSImage {
        switch style {
        case .icon: icon
        case .wordmark: wordmark
        }
    }

    private static let icon = template(named: "DDockMark", size: NSSize(width: 18, height: 18))
    /// Same letter height as before the tracking change; the extra is only as wide as the lockup.
    /// Aspect matches the cropped `DDockWordmark` viewBox so AppKit's SVG size cannot pad the sides.
    private static let wordmarkAspect: CGFloat = 496 / 59
    private static let wordmark = template(named: "DDockWordmark",
                                          size: NSSize(width: 12 * wordmarkAspect, height: 18),
                                          aspect: wordmarkAspect)

    private static func template(named name: String, size: NSSize, aspect: CGFloat? = nil) -> NSImage {
        let source = NSImage(named: name)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let source else { return false }
            source.draw(in: Self.fitted(aspect.map { NSSize(width: $0, height: 1) } ?? source.size,
                                        in: rect),
                        from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Letterboxing keeps the mark's proportions when the canvas is square or short.
    private static func fitted(_ size: NSSize, in rect: NSRect) -> NSRect {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let scale = min(rect.width / width, rect.height / height)
        let fitted = NSSize(width: width * scale, height: height * scale)
        return NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}
