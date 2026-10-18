import AppKit

/// A tint as hue and saturation, so palette choices stay independent of SwiftUI and AppKit.
struct DockIslandColor: Equatable, Hashable, Sendable {
    /// Degrees, 0 to 360.
    var hue: Double
    /// 0 to 1.
    var saturation: Double

    static let untinted = DockIslandColor(hue: 220, saturation: 0)

    /// The system accent colour, resolved at draw time. Encoded as a NaN hue.
    static let accent = DockIslandColor(hue: .nan, saturation: 1)
    var isAccent: Bool { hue.isNaN }
}

/// Resolves an island's colour from its own tint, the dock-wide mode, and its contents.
enum DockIslandPalette {
    /// The concept's palette: blue system, purple tile, gold apps, teal running, graphite extras.
    static func color(for kind: DockIslandKind, customIndex: Int = 0) -> DockIslandColor {
        switch kind {
        case .tile: DockIslandColor(hue: 268, saturation: 0.70)
        case .pinned: DockIslandColor(hue: 40, saturation: 0.60)
        case .running: DockIslandColor(hue: 172, saturation: 0.70)
        case .utilities: DockIslandColor(hue: 220, saturation: 0.14)
        case .custom: customPalette[customIndex % customPalette.count]
        }
    }

    /// Split-off islands cycle through these so neighbours never share a hue.
    private static let customPalette: [DockIslandColor] = [
        DockIslandColor(hue: 212, saturation: 0.85), DockIslandColor(hue: 340, saturation: 0.70),
        DockIslandColor(hue: 120, saturation: 0.55), DockIslandColor(hue: 18, saturation: 0.80),
        DockIslandColor(hue: 290, saturation: 0.60), DockIslandColor(hue: 190, saturation: 0.75),
    ]

    static func color(for tint: DockIslandTint) -> DockIslandColor? {
        switch tint {
        case .automatic: nil
        case .blue: DockIslandColor(hue: 212, saturation: 0.85)
        case .purple: DockIslandColor(hue: 268, saturation: 0.70)
        case .gold: DockIslandColor(hue: 40, saturation: 0.60)
        case .teal: DockIslandColor(hue: 172, saturation: 0.70)
        case .graphite: DockIslandColor(hue: 220, saturation: 0.14)
        case .pink: DockIslandColor(hue: 340, saturation: 0.70)
        case .green: DockIslandColor(hue: 120, saturation: 0.55)
        case .orange: DockIslandColor(hue: 18, saturation: 0.80)
        case .none: .untinted
        }
    }

    /// The colour an island draws with.
    /// - Parameter iconColors: Sampled icon colours for the island's slots, used by `fromIcons`.
    static func resolve(_ span: DockIslandSpan, mode: DockIslandTintMode, iconColors: [DockIslandColor]) -> DockIslandColor {
        if let own = color(for: span.island.tint) { return own }
        switch mode {
        case .byKind: return color(for: span.island.kind, customIndex: span.customIndex)
        case .accent: return .accent
        case .none: return .untinted
        case .fromIcons: return DockIconTintSampler.blend(iconColors) ?? DockIslandColor(hue: 220, saturation: 0.10)
        }
    }
}

/// Finds the dominant hue of an icon by averaging its saturated pixels.
///
/// Sampling is cheap (a 16×16 draw) but not free, so callers cache by item identity and sample
/// off the pointer path. Icons without a saturated colour, such as Terminal, return nil.
enum DockIconTintSampler {
    private static let side = 16

    static func color(of image: NSImage) -> DockIslandColor? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var x = 0.0, y = 0.0, weight = 0.0
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha, g = Double(pixels[index + 1]) / 255 / alpha, b = Double(pixels[index + 2]) / 255 / alpha
            let high = max(r, g, b), low = min(r, g, b)
            let lightness = (high + low) / 2
            guard high > low, lightness > 0.12, lightness < 0.92 else { continue }
            let saturation = (high - low) / (1 - abs(2 * lightness - 1))
            guard saturation >= 0.25 else { continue }
            var hue: Double
            if high == r { hue = ((g - b) / (high - low)).truncatingRemainder(dividingBy: 6) }
            else if high == g { hue = (b - r) / (high - low) + 2 }
            else { hue = (r - g) / (high - low) + 4 }
            hue *= 60
            if hue < 0 { hue += 360 }
            let w = saturation * saturation
            x += cos(hue * .pi / 180) * w
            y += sin(hue * .pi / 180) * w
            weight += w
        }
        return blend(sums: (x, y, weight))
    }

    /// Circular mean of several sampled colours; the spread of hues lowers the saturation so a
    /// mixed island reads as a soft neutral rather than a random hue.
    static func blend(_ colors: [DockIslandColor]) -> DockIslandColor? {
        var x = 0.0, y = 0.0, weight = 0.0
        for color in colors where !color.isAccent {
            let radians = color.hue * .pi / 180
            x += cos(radians) * color.saturation
            y += sin(radians) * color.saturation
            weight += color.saturation
        }
        return blend(sums: (x, y, weight))
    }

    private static func blend(sums: (x: Double, y: Double, weight: Double)) -> DockIslandColor? {
        guard sums.weight > 0.5 else { return nil }
        var hue = atan2(sums.y, sums.x) * 180 / .pi
        if hue < 0 { hue += 360 }
        let agreement = hypot(sums.x, sums.y) / sums.weight
        return DockIslandColor(hue: hue.rounded(), saturation: min(1, 0.30 + 0.55 * agreement))
    }
}
