import SwiftUI

/// A short hop, anchored at the dock edge, when something lands in a tile.
///
/// The trigger is the tile's own arrival count in `DockInteraction.arrivals`, so an arrival elsewhere
/// never replays it. Reduce Motion skips the hop; the tile's badge or contents still change.
struct DockTileArrivalBounce: ViewModifier {
    let hitID: String
    let interaction: DockInteraction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: interaction.arrivals[hitID, default: 0]) { content, scale in
            content.scaleEffect(scale, anchor: anchor)
        } keyframes: { _ in
            if reduceMotion {
                LinearKeyframe(1.0, duration: 0.01)
            } else {
                CubicKeyframe(1.2, duration: 0.12)
                CubicKeyframe(0.94, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
        }
    }

    /// The edge the tile rests on, so the hop grows away from it.
    private var anchor: UnitPoint {
        switch interaction.layout.edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }
}
