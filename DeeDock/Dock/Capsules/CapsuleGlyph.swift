import AppKit
import SwiftUI

/// The Session Capsules mark: a tilted, two-shell pill drawn as vector art.
///
/// The `archivebox` symbol this replaces read as a storage crate, not a capsule, so the mark is drawn
/// rather than borrowed: a pale sleeve over a tinted shell, a seam shadow where they meet, cylindrical
/// shading across the short axis, and one specular highlight. Every measurement derives from `size`,
/// so the same mark serves a 14pt panel header and a 64pt Dock tile without a second asset.
struct CapsuleGlyph: View {
    var size: CGFloat
    var tint: Color = .accentColor
    /// Tilt inside the square box. The default keeps both shells legible at Dock tile sizes.
    var angle: Angle = .degrees(-38)
    /// Drop shadows help on the Dock but muddy the mark inline in a panel row.
    var elevated = true

    private var shellWidth: CGFloat { size * 0.40 }
    private var shellHeight: CGFloat { size * 0.82 }
    private var hairline: CGFloat { max(0.5, size * 0.016) }

    var body: some View {
        ZStack {
            shells
            cylinder
            specular
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(rim, lineWidth: hairline) }
        .frame(width: shellWidth, height: shellHeight)
        .shadow(color: .black.opacity(elevated ? 0.3 : 0), radius: size * 0.05, y: size * 0.025)
        .rotationEffect(angle)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var shape: Capsule { Capsule(style: .continuous) }

    /// Pale sleeve above, tinted shell below, with the sleeve's shadow falling across the join.
    private var shells: some View {
        VStack(spacing: 0) {
            Rectangle().fill(LinearGradient(
                colors: [.white, Color.white.mix(with: tint, by: 0.14)],
                startPoint: .top, endPoint: .bottom))
            Rectangle().fill(LinearGradient(
                colors: [tint.mix(with: .white, by: 0.24), tint.mix(with: .black, by: 0.18)],
                startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .center) {
            LinearGradient(colors: [.black.opacity(0.34), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: max(1, size * 0.08))
                .offset(y: max(0.5, size * 0.04))
        }
        .overlay(alignment: .center) {
            Rectangle().fill(.black.opacity(0.2)).frame(height: hairline)
        }
    }

    /// Shading across the short axis; without it the pill reads as a flat sticker.
    private var cylinder: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.24), location: 0),
            .init(color: .clear, location: 0.3),
            .init(color: .white.opacity(0.16), location: 0.5),
            .init(color: .clear, location: 0.68),
            .init(color: .black.opacity(0.28), location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }

    private var specular: some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: shellWidth * 0.17, height: shellHeight * 0.6)
            .blur(radius: max(0.4, size * 0.028))
            .offset(x: -shellWidth * 0.25, y: -shellHeight * 0.09)
    }

    private var rim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.28)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension CapsuleGlyph {
    /// Rasterized mark for the places that still need an `NSImage`, such as drag previews.
    ///
    /// Rendered once per call site and cached by the caller: `ImageRenderer` walks the whole view tree,
    /// which is far too costly to repeat on every Dock refresh.
    @MainActor static func image(size: CGFloat = 128) -> NSImage {
        let renderer = ImageRenderer(content: CapsuleGlyph(size: size).frame(width: size, height: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = renderer.cgImage else { return NSImage(size: NSSize(width: size, height: size)) }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

/// A capsule's applications, twined into an overlapping fan with a count for the ones that don't fit.
///
/// Real application artwork identifies a saved capsule far faster than a generic badge does, and the
/// overlap plus alternating tilt keeps the whole fan inside the space one badge used to occupy.
struct TwinedAppIconStack: View {
    let icons: [NSImage]
    let size: CGFloat
    var maximum = 3
    /// Fraction of each icon hidden by the next one.
    var overlap: CGFloat = 0.42

    private var shown: [NSImage] { Array(icons.prefix(maximum)) }
    private var overflow: Int { max(0, icons.count - maximum) }
    /// One more slot than the icons occupy, so the fan stays centred on the tile.
    private var slots: Int { shown.count + (overflow > 0 ? 1 : 0) }

    var body: some View {
        HStack(spacing: -size * overlap) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, icon in
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(tilt(index)))
                    .shadow(color: .black.opacity(0.45), radius: size * 0.07, x: -size * 0.03)
                    .zIndex(Double(slots - index))
            }
            if overflow > 0 { counter }
        }
        .accessibilityHidden(true)
    }

    /// Drawn a little smaller than the frame because application artwork carries its own padding.
    private var counter: some View {
        Text(.capsulesMoreApplications(count: overflow))
            .font(.system(size: size * 0.34, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.1)
            .frame(minWidth: size * 0.78, minHeight: size * 0.78)
            .background(Color.accentColor.gradient, in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, size * 0.04)) }
            .rotationEffect(.degrees(tilt(shown.count)))
            .shadow(color: .black.opacity(0.45), radius: size * 0.07, x: -size * 0.03)
            .padding(.leading, size * 0.3)
    }

    /// Fan the stack around its centre so no icon sits perfectly upright behind another.
    private func tilt(_ index: Int) -> Double {
        guard slots > 1 else { return 0 }
        let centre = Double(slots - 1) / 2
        return (Double(index) - centre) * 8
    }
}

/// A saved capsule's Dock tile: the applications it holds, twisted into a stack.
///
/// A capsule is identified by what it contains, so the tile shows real application artwork rather than
/// a generic mark. The front card stands upright and the ones behind it turn alternately left and
/// right — +10°, -10°, +20° — so their corners emerge on *both* sides of the upright card. Turning them
/// all the same way, which is the obvious reading of a twisted stack, does not work: the cards hide
/// behind the front one and the little that escapes on a single side makes the front icon itself look
/// crooked. A capsule holding one application would be indistinguishable from that application's own
/// tile, so a lone icon gets a blank card on each side instead. The widest turn is what sets
/// `cardSize`: rotation grows a card's bounding box, and the fan has to stay clear of its neighbours.
struct SessionCapsuleStack: View {
    let icons: [NSImage]
    let size: CGFloat
    /// Beyond four cards the fan stops adding depth and starts adding clutter.
    var maximum = 4
    /// Turn added by each pair of cards behind the front one.
    var step: Angle = .degrees(10)

    /// Cards are drawn a little under the tile's full size because rotation grows their bounding box.
    private var cardSize: CGFloat { size * 0.92 }
    private var corner: CGFloat { cardSize * 0.22 }

    /// Cards grow as they go back, so each one shows along a whole edge and not only at the corners.
    private func cardSize(depth: Int) -> CGFloat { cardSize * (1 + 0.05 * CGFloat(depth)) }
    private var shown: [NSImage] { Array(icons.prefix(maximum)) }
    private var overflow: Int { max(0, icons.count - maximum) }

    var body: some View {
        ZStack {
            if shown.count <= 1 {
                ghost(depth: 2)
                ghost(depth: 1)
            }
            // Reversed so the deepest card is drawn first and the upright one lands on top.
            ForEach(Array(shown.enumerated()).reversed(), id: \.offset) { index, icon in
                card(icon, depth: index)
            }
            if shown.isEmpty { CapsuleGlyph(size: cardSize * 0.6, elevated: false) }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { if overflow > 0 { counter } }
        .accessibilityHidden(true)
    }

    private func card(_ icon: NSImage, depth: Int) -> some View {
        let side = cardSize(depth: depth)
        return Image(nsImage: icon).resizable().interpolation(.high)
            .frame(width: side, height: side)
            // Lifted, not dimmed: a dark icon dimmed behind a dark icon disappears into it.
            .brightness(0.05 * Double(depth))
            .saturation(1 - 0.08 * Double(depth))
            .shadow(color: .black.opacity(0.45), radius: cardSize * 0.045, y: cardSize * 0.015)
            // A pale halo traces the artwork's own alpha, so same-coloured cards still separate.
            // The front card is left clean: its silhouette is the one that should read as an icon.
            .shadow(color: depth > 0 ? .white.opacity(0.3) : .clear, radius: cardSize * 0.02)
            .rotationEffect(angle(depth))
    }

    /// The cards that say "stack" when the artwork alone cannot: blank layers behind a lone icon.
    ///
    /// Mid-grey rather than near-black on purpose. Behind a dark application icon a dark card merges
    /// with it, and the pair then reads as one crooked tile instead of a stack.
    private func ghost(depth: Int) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.secondary.opacity(0.45))
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.ultraThinMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, cardSize * 0.018))
            }
            .frame(width: cardSize, height: cardSize)
            .brightness(-0.1 * Double(depth))
            .shadow(color: .black.opacity(0.45), radius: cardSize * 0.045, y: cardSize * 0.015)
            .rotationEffect(angle(depth))
    }

    /// Alternating turns: the odd cards lean one way, the even cards the other, widening every pair.
    private func angle(_ depth: Int) -> Angle {
        guard depth > 0 else { return .zero }
        let magnitude = Double((depth + 1) / 2)
        return step * (depth.isMultiple(of: 2) ? -magnitude : magnitude)
    }

    /// The same count badge the Session Capsules tile wears, so both read as "and this many more".
    private var counter: some View {
        Text(.capsulesMoreApplications(count: overflow))
            .font(.system(size: max(9, size * 0.2), weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, max(4, size * 0.09))
            .padding(.vertical, max(1, size * 0.02))
            .background(Color.accentColor, in: .capsule)
            .overlay { Capsule().strokeBorder(.background.opacity(0.7), lineWidth: 1) }
            .offset(x: size * 0.04, y: size * 0.02)
    }
}

#if DEBUG
#Preview("Capsule Glyph") {
    HStack(spacing: 24) {
        CapsuleGlyph(size: 64)
        CapsuleGlyph(size: 32)
        CapsuleGlyph(size: 16, elevated: false)
        CapsuleGlyph(size: 64, tint: .purple, angle: .degrees(0))
    }
    .padding(32)
    .background(.black)
}
#endif
