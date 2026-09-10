import SwiftUI

/// The plant drawing shared by the Settings greenhouse and the dock's Action Tiles.
///
/// Pure presentation: it never runs a shortcut. Watering happens in the views that own the
/// button, through ``ActionTilesController/water(_:)``. Keeping the artwork here means a plant
/// in Settings and a plant in the dock cannot drift apart.
///
/// Healthy and wilted differ in silhouette, not only in brightness: a wilted plant droops, loses
/// its green, and shows a bare stem, so it stays legible at dock size and in monochrome.
struct ShortcutGreenhouseArtwork: View {
    /// Whether the pinned shortcut still exists. Wilt is a discovery result, not a run failure.
    let health: ShortcutGreenhouseHealth
    /// Run state; a busy plant shows watering feedback.
    let status: ActionTileStatus
    /// Edge length of the square the plant is drawn into.
    var size: CGFloat = 44
    /// Caller-supplied Reduce Motion value, so the dock and Settings can pass their own environment.
    var reduceMotion = false

    private var wilted: Bool { health == .wilted }

    var body: some View {
        ZStack(alignment: .bottom) {
            plant
                // The stem grows out of the pot, so the whole plant leans from its base.
                .rotationEffect(.degrees(wilted ? 9 : 0), anchor: .bottom)
                .saturation(wilted ? 0.35 : 1)
                .opacity(wilted ? 0.7 : 1)
                .offset(y: -size * 0.18)
            pot
            if status.busy {
                waterDrop
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var plant: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(stemStyle)
                .frame(width: max(1.5, size * 0.07), height: size * 0.42)
            leaf(scale: 0.32, flipped: false)
            leaf(scale: 0.27, flipped: true)
        }
        .frame(width: size, height: size * 0.6, alignment: .bottom)
    }

    private func leaf(scale: CGFloat, flipped: Bool) -> some View {
        let side: CGFloat = flipped ? -1 : 1
        // Healthy leaves lift away from the stem; wilted leaves fold past horizontal and sag.
        let angle = wilted ? 132.0 : 40.0
        return Image(systemName: "leaf.fill")
            .font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(foliageStyle)
            .rotationEffect(.degrees(angle * side))
            .offset(x: size * 0.15 * side,
                    y: wilted ? -size * 0.16 : -size * 0.3)
    }

    private var pot: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: size * 0.07,
                               bottomTrailingRadius: size * 0.07,
                               style: .continuous)
            .fill(Color.brown.gradient)
            .frame(width: size * 0.5, height: size * 0.24)
            .overlay(alignment: .top) {
                // Soil line, so the stem reads as planted rather than floating in a cup.
                Capsule()
                    .fill(.black.opacity(0.28))
                    .frame(height: size * 0.05)
            }
    }

    @ViewBuilder private var waterDrop: some View {
        let drop = Image(systemName: "drop.fill")
            .font(.system(size: size * 0.22, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        if reduceMotion {
            drop.offset(y: -size * 0.42)
        } else {
            drop.phaseAnimator([0.0, 1.0]) { content, phase in
                content
                    .offset(y: -size * (0.68 - 0.26 * phase))
                    .opacity(1 - 0.7 * phase)
            } animation: { _ in
                .easeIn(duration: 0.8)
            }
        }
    }

    private var foliageStyle: AnyShapeStyle {
        wilted ? AnyShapeStyle(Color.brown) : AnyShapeStyle(Color.green.gradient)
    }

    private var stemStyle: AnyShapeStyle {
        wilted ? AnyShapeStyle(Color.brown.opacity(0.9)) : AnyShapeStyle(Color.green.opacity(0.85))
    }
}

#if DEBUG
#Preview("Healthy and wilted") {
    HStack(spacing: 28) {
        ShortcutGreenhouseArtwork(health: .healthy, status: .idle, size: 72)
        ShortcutGreenhouseArtwork(health: .wilted, status: .idle, size: 72)
    }
    .padding(24)
}

#Preview("Watering") {
    HStack(spacing: 28) {
        ShortcutGreenhouseArtwork(health: .healthy, status: .running, size: 72)
        ShortcutGreenhouseArtwork(health: .healthy, status: .running, size: 72, reduceMotion: true)
    }
    .padding(24)
}

#Preview("Dock size") {
    HStack(spacing: 12) {
        ShortcutGreenhouseArtwork(health: .healthy, status: .idle, size: 44)
        ShortcutGreenhouseArtwork(health: .wilted, status: .idle, size: 44)
    }
    .padding(16)
    .preferredColorScheme(.dark)
}
#endif
