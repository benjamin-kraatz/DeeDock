import AppKit
import SwiftUI

/// The colored light under one glass island.
///
/// The reference dock is not one neutral bar cut into pieces. Each capsule carries the hue of
/// the icons inside it and spills that hue outward, the way a light sits on the desktop.
@MainActor
enum DockIslandTint {
    /// Dominant hue of the tiles in `range`.
    ///
    /// Hues are averaged on the color circle so a blue icon and a purple icon meet in between
    /// instead of cancelling through gray. An island with no chromatic icon keeps a distinct
    /// fallback so an empty or gray section still reads as its own light.
    static func color(for slots: [DockRenderSlot], in range: Range<Int>, island index: Int) -> Color {
        let upper = min(range.upperBound, slots.count)
        guard range.lowerBound >= 0, range.lowerBound < upper else { return fallback(index) }
        var x = 0.0
        var y = 0.0
        var weight = 0.0
        for slot in slots[range.lowerBound..<upper] {
            for sample in samples(of: slot) {
                let angle = sample.hue * 2 * .pi
                x += cos(angle) * sample.weight
                y += sin(angle) * sample.weight
                weight += sample.weight
            }
        }
        guard weight > 0 else { return fallback(index) }
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return Color(hue: hue, saturation: 0.82, brightness: 1)
    }

    private struct Sample {
        var hue: Double
        var weight: Double
    }

    private static func samples(of slot: DockRenderSlot) -> [Sample] {
        switch slot {
        case .launcher:
            // The launcher tile is an indigo grid. It has no application icon to sample.
            return [Sample(hue: 0.73, weight: 1)]
        case .focus:
            return [Sample(hue: 0.50, weight: 1)]
        case .action:
            return [Sample(hue: 0.78, weight: 1)]
        case .melt(let pair, let index):
            guard pair.icons.indices.contains(index) else { return [] }
            let identity = pair.applicationIDs.indices.contains(index) ? pair.applicationIDs[index] : pair.id.uuidString
            return hue(of: pair.icons[index], identity: identity).map { [Sample(hue: $0, weight: 1)] } ?? []
        case .gap, .group:
            return []
        default:
            guard let icon = slot.icon else { return [] }
            return hue(of: icon, identity: slot.id).map { [Sample(hue: $0, weight: 1)] } ?? []
        }
    }

    private static func hue(of icon: NSImage, identity: String) -> Double? {
        guard let accent = DockIconAccent.accent(for: icon, identity: identity),
              let color = NSColor(accent).usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(hue)
    }

    /// Blue, violet, gold, cyan, steel. Same order as the island reference, used only when an
    /// island's artwork has no hue of its own.
    private static func fallback(_ index: Int) -> Color {
        let hues = [0.64, 0.75, 0.10, 0.50, 0.59]
        let saturations = [0.78, 0.58, 0.78, 0.72, 0.28]
        let wrapped = ((index % hues.count) + hues.count) % hues.count
        return Color(hue: hues[wrapped], saturation: saturations[wrapped], brightness: 1)
    }
}

/// Soft colored light pooled on the outward side of one island.
///
/// The pool is wider than the capsule and shifted toward the screen edge, so the bright core
/// sits on the lip of the glass and the rest falls off across the desktop. `frame` is the
/// capsule in the same coordinate space as this view.
struct DockIslandGlow: View {
    let color: Color
    let frame: CGRect
    let edge: DockEdge

    private var length: CGFloat { edge.isVertical ? frame.height : frame.width }
    private var thickness: CGFloat { edge.isVertical ? frame.width : frame.height }

    var body: some View {
        let outward = edge.offset(CGSize(width: 0, height: thickness * 0.46))
        ZStack {
            RoundedRectangle(cornerRadius: thickness, style: .continuous)
                .fill(color.opacity(0.72))
                .frame(width: poolSize.width, height: poolSize.height)
                .blur(radius: max(10, thickness * 0.38))
            Capsule()
                .fill(color)
                .frame(width: filamentSize.width, height: filamentSize.height)
                .blur(radius: max(4, thickness * 0.12))
        }
        .position(x: frame.midX + outward.width, y: frame.midY + outward.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Wide floor pool. Long axis follows the island; the short axis is the dock's thickness.
    private var poolSize: CGSize {
        let along = length * 1.08
        let across = thickness * 1.15
        return edge.isVertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    }

    /// Bright filament along the outward lip, before the pool falls off.
    private var filamentSize: CGSize {
        let along = length * 0.9
        let across = max(8, thickness * 0.26)
        return edge.isVertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    }
}

#if DEBUG
#Preview("Island lights on black") {
    let colors: [Color] = [
        Color(hue: 0.64, saturation: 0.78, brightness: 1),
        Color(hue: 0.75, saturation: 0.58, brightness: 1),
        Color(hue: 0.10, saturation: 0.78, brightness: 1),
        Color(hue: 0.50, saturation: 0.72, brightness: 1),
        Color(hue: 0.59, saturation: 0.28, brightness: 1)
    ]
    let widths: [CGFloat] = [210, 68, 320, 196, 230]
    HStack(alignment: .center, spacing: 22) {
        ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
            let height: CGFloat = 160
            let capsule = CGRect(x: 0, y: (height - 58) / 2, width: width, height: 58)
            ZStack {
                DockIslandGlow(color: colors[index], frame: capsule, edge: .bottom)
                DockBackgroundView(reduceTransparency: false, cornerRadius: 29, tint: colors[index], edge: .bottom)
                    .frame(width: width, height: 58)
            }
            .frame(width: width, height: height)
        }
    }
    .padding(48)
    .background(Color.black)
}
#endif
