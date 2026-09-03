import AppKit
import SwiftUI

/// The dominant chromatic hue of an application icon, cached per identity.
///
/// The shaders already read the artwork's local colors, but a per-pixel bleed alone has no
/// sense of what an icon *is*: a mostly-white icon with a red mark reads as white. One
/// dominant hue restores that identity, so WhatsApp glows green and Ghostty violet.
///
/// Each icon is reduced to a 16×16 bitmap once. Hues are averaged on the colour circle,
/// weighted by alpha and by squared saturation, so a small vivid mark outvotes a large grey
/// field and opposing hues do not cancel into a muddy average without being noticed.
@MainActor
enum DockIconAccent {
    /// Keyed by `ApplicationReference.id`. Bounded by the number of applications the user
    /// has ever seen in one session, and each entry is three floats.
    private static var cache: [String: Color?] = [:]

    /// Alpha below this contributes no colour; it is antialiasing, not artwork.
    private static let visible = 0.1
    /// Below these the icon is treated as achromatic and the shader keeps its own palette.
    private static let minimumAgreement = 0.35
    private static let minimumSaturation = 0.18

    /// Returns the icon's dominant hue, or `nil` when the artwork has no usable one.
    ///
    /// Rasterizing is done once per identity; repeat calls are a dictionary lookup, which is
    /// what makes this safe to read from a view body on every frame.
    static func accent(for icon: NSImage, identity: String) -> Color? {
        if let cached = cache[identity] { return cached }
        let extracted = extract(icon)
        cache[identity] = extracted
        return extracted
    }

    /// Drops cached artwork colours; the next request re-reads the icon.
    static func invalidate() { cache.removeAll() }

    private static func extract(_ icon: NSImage) -> Color? {
        let side = 16
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = bitmap.bitmapData else { return nil }

        var x = 0.0, y = 0.0, weightTotal = 0.0, saturationTotal = 0.0
        for offset in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > visible else { continue }
            // This representation stores premultiplied components; recover the drawn colour
            // before measuring saturation, or every translucent pixel reads as near-black.
            let red = min(1, Double(pixels[offset]) / 255 / alpha)
            let green = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let blue = min(1, Double(pixels[offset + 2]) / 255 / alpha)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, ignored: CGFloat = 0
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &ignored)
            let weight = alpha * Double(saturation * saturation * brightness)
            guard weight > 0 else { continue }
            let angle = Double(hue) * 2 * .pi
            x += cos(angle) * weight
            y += sin(angle) * weight
            saturationTotal += Double(saturation) * weight
            weightTotal += weight
        }
        guard weightTotal > 0 else { return nil }
        // A short resultant vector means the icon's hues disagree; averaging them would
        // invent a colour the icon does not contain.
        let agreement = (x * x + y * y).squareRoot() / weightTotal
        guard agreement > minimumAgreement, saturationTotal / weightTotal > minimumSaturation else { return nil }
        let hue = atan2(y, x) / (2 * .pi)
        // Saturation and brightness are fixed: this is emitted light, not a paint sample.
        return Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.85, brightness: 1)
    }
}
