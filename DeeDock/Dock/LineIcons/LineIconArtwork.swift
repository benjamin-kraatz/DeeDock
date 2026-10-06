import AppKit
import CoreGraphics
import SwiftUI

/// Draws a catalog glyph as clean white line art, centered in a tile-sized square.
///
/// Strokes scale with the tile, so magnification thickens them in proportion instead of letting
/// small icons look heavy and large ones look thin.
struct LineIconArtwork: View {
    let glyph: LineIconGlyph
    /// The tile's full icon size in points.
    let size: CGFloat
    var color: Color = .white

    /// Share of the tile the 24-point box fills; the rest matches the inset of native artwork.
    static let boxFraction: CGFloat = 0.62
    /// Stroke width in catalog units. Lucide's own default of 2 reads too heavy on dark glass.
    static let strokeWidth: CGFloat = 1.5

    var body: some View {
        let box = size * Self.boxFraction * (glyph.isFilledMark ? 0.86 : 1)
        let scale = box / LineIconPath.canvas
        ZStack {
            if glyph.fill != nil {
                LineIconShape(glyph: glyph, part: .fill).fill(color)
            }
            if glyph.stroke != nil {
                LineIconShape(glyph: glyph, part: .stroke)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.strokeWidth * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: box, height: box)
        .frame(width: size, height: size)
    }
}

/// One part of a glyph, scaled from the 24-point catalog box into the proposed rectangle.
struct LineIconShape: Shape {
    enum Part { case stroke, fill }
    let glyph: LineIconGlyph
    let part: Part

    func path(in rect: CGRect) -> Path {
        guard let source = part == .stroke ? glyph.stroke : glyph.fill else { return Path() }
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / LineIconPath.canvas, y: rect.height / LineIconPath.canvas)
        return Path(source).applying(transform)
    }
}

/// What lights up behind a line glyph while the pointer is over its tile.
enum DockLineGlow {
    /// The app's own artwork, blurred, so each app glows in its brand colors.
    case artwork(NSImage)
    /// A shared magenta, orange, and blue spectrum for tiles without colorful artwork.
    case spectrum
}

/// A tile's line glyph with the glow its hover state calls for.
struct DockLineIcon {
    let glyph: LineIconGlyph
    var glow: DockLineGlow = .spectrum
}

/// A line glyph over a soft colored glow that fades in on hover.
///
/// The glow is drawn outside the tile's square and never takes hit-testing, so it cannot change the
/// button region or click-through geometry. Reduce Transparency replaces the blurred glow with a
/// brighter glyph; Reduce Motion shows and hides it without a fade.
struct DockLineIconArtwork: View {
    let icon: DockLineIcon
    let size: CGFloat
    let hovered: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    private var glowing: Bool { hovered && !reduceTransparency }

    var body: some View {
        LineIconArtwork(glyph: icon.glyph, size: size,
                        color: .white.opacity(hovered || reduceTransparency ? 1 : 0.92))
            // At rest a faint dark edge keeps white lines legible on light wallpapers seen through the glass.
            .shadow(color: glowing ? .white.opacity(0.55) : .black.opacity(0.35),
                    radius: glowing ? size * 0.06 : max(0.5, size * 0.015))
            .background {
                // Inserted only while hovered: a resting dock would otherwise pay for one blur per tile.
                if glowing {
                    DockLineGlowView(glow: icon.glow, size: size)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: hovered ? 0.18 : 0.32), value: glowing)
    }
}

/// The blurred color field behind a hovered glyph.
private struct DockLineGlowView: View {
    let glow: DockLineGlow
    let size: CGFloat

    var body: some View {
        Group {
            switch glow {
            case .artwork(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.low)
                    .saturation(1.35)
                    .frame(width: size * 0.9, height: size * 0.9)
            case .spectrum:
                Circle()
                    .fill(AngularGradient(colors: [.pink, .orange, .blue, .purple, .pink], center: .center))
                    .frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .blur(radius: size * 0.26)
        .opacity(0.9)
        .frame(width: size, height: size)
    }
}

extension LineIconArtwork {
    /// Rasterized glyph for a native drag image. Call it when a drag starts, not on each pointer move.
    @MainActor static func image(glyph: LineIconGlyph, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: LineIconArtwork(glyph: glyph, size: size))
        renderer.scale = 2
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

#if DEBUG
#Preview("Line glyphs, resting and hovered") {
    let glyph = LineIconGlyph(id: "preview:compass",
                              stroke: LineIconPath.parse("M22 12C22 17.52 17.52 22 12 22C6.48 22 2 17.52 2 12C2 6.48 6.48 2 12 2C17.52 2 22 6.48 22 12Z M16.24 7.76L14.44 13.17L7.76 16.24L9.56 10.83Z"),
                              fill: nil)
    HStack(spacing: 28) {
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: false,
                            reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: true,
                            reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph, glow: .artwork(NSImage(named: NSImage.applicationIconName)!)),
                            size: 64, hovered: true, reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: true,
                            reduceMotion: true, reduceTransparency: true)
    }
    .padding(40)
    .background(.black)
}
#endif
