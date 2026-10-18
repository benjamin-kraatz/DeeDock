import SwiftUI

/// A running-state marker shared by live icons and inert Settings samples.
/// Hidden markers retain the reserved strip so appearance changes cannot shift icons or hit regions.
struct DockRunningIndicator: View {
    let style: DockSettings.RunningIndicatorStyle
    let edge: DockEdge
    /// Inside an island the marker takes the island's tint and a soft matching glow.
    @Environment(\.dockIslandTint) private var islandTint

    var body: some View {
        Group {
            switch style {
            case .dot:
                Circle().frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
            case .bar:
                Capsule().frame(width: edge.isVertical ? DockGeometry.indicatorSize : 16,
                                height: edge.isVertical ? 16 : DockGeometry.indicatorSize)
            case .square:
                Rectangle().frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
            case .targetLock, .orbit, .stardust, .powerBadge, .hidden:
                Color.clear.frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
            }
        }
        .foregroundStyle(islandTint ?? .primary.opacity(0.8))
        .shadow(color: islandTint?.opacity(0.9) ?? .clear, radius: islandTint == nil ? 0 : 3)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

