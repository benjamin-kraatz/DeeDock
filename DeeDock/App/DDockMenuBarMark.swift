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
    private static let wordmarkAspect: CGFloat = 388 / 59
    /// The logotype spells DOKK. During an alias week the menu bar draws the longer name instead.
    private static let wordmark: NSImage = ProductAlias.presentsFestiveName
        ? festiveWordmark()
        : template(named: "DDockWordmark",
                   size: NSSize(width: 12 * wordmarkAspect, height: 18),
                   aspect: wordmarkAspect)

    /// Template text for the alias. The letter spacing of the DOKK logotype has no room for a second word.
    private static func festiveWordmark() -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .heavy)
        let text = NSAttributedString(string: ProductAlias.festive, attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
        ])
        let bounds = text.size()
        let size = NSSize(width: ceil(bounds.width) + 2, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            text.draw(at: NSPoint(x: 1, y: (rect.height - bounds.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

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
