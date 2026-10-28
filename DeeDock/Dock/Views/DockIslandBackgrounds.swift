import SwiftUI

/// Everything the surface needs to draw islands: which slots form each island, the colour each
/// resolved to, and the dock-wide style. Built by the panel once per projection, never per frame.
struct DockIslandPresentation: Equatable {
    var spans: [DockIslandSpan]
    /// One colour per span, resolved from the tint mode and sampled icons.
    var colors: [DockIslandColor]
    var settings: DockIslandSettings
}

/// Draws one tinted glass block per island, placed on the layout's island frames.
///
/// Replaces the single `DockBackgroundView` while islands are on. Frames come from the same
/// magnified sizes as the icons, so an island stretches with hover exactly as the one surface did.
struct DockIslandBackgrounds: View {
    let presentation: DockIslandPresentation
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let cornerRadius: CGFloat
    let idleOpacity: Double
    let idleAnimation: Animation?
    let reduceTransparency: Bool

    var body: some View {
        let frames = layout.islandFrames(sizes: sizes)
        // Native Liquid Glass sets its own blur; the mockup's 32pt blur has no API counterpart.
        ForEach(Array(zip(presentation.spans, frames).enumerated()), id: \.element.0.id) { index, pair in
            let (span, frame) = pair
            let color = index < presentation.colors.count ? presentation.colors[index] : .untinted
            DockIslandBackgroundView(
                style: presentation.settings.style,
                color: color,
                tintStrength: presentation.settings.tintStrength,
                glow: presentation.settings.glow,
                edge: layout.edge,
                reduceTransparency: reduceTransparency,
                showsLamp: presentation.settings.showsLamp,
                lampThickness: presentation.settings.lampThickness,
                lampOpacity: presentation.settings.lampOpacity / 100,
                rimWidth: min(presentation.settings.rim, presentation.settings.padding * 0.6),
                cornerRadius: min(cornerRadius, min(frame.width, frame.height) / 2),
                idleOpacity: idleOpacity,
                accessibilityName: String(localized: .islandsAccessibilityIsland(span.island.displayName))
            )
            .animation(idleAnimation, value: idleOpacity)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}
