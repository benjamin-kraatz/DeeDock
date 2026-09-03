import SwiftUI

/// A running-state marker shared by live icons and inert Settings samples.
/// Hidden markers retain the reserved strip so appearance changes cannot shift icons or hit regions.
struct DockRunningIndicator: View {
    let style: DockSettings.RunningIndicatorStyle
    let edge: DockEdge

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
            case .targetLock, .orbit, .stardust, .powerBadge, .glitch, .plasma, .hologram,
                 .solarFlare, .prism, .lavaChrome, .singularity, .hidden:
                Color.clear.frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
            }
        }
        .foregroundStyle(.primary.opacity(0.8))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

