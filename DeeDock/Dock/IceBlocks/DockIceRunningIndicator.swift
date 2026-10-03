import SwiftUI

/// The Ice Blocks running marker: a short glowing bar in its block's tint. It fills the same
/// reserved strip as `DockRunningIndicator`, so switching styles never moves an icon.
struct DockIceRunningIndicator: View {
    let tint: Color
    let edge: DockEdge

    var body: some View {
        // Dropped toward the screen edge into the block's extra room, so the bar floats between
        // the icon and the rim instead of touching the artwork.
        let drop = edge.offset(CGSize(width: 0, height: DockIceMetrics.indicatorDrop))
        Capsule()
            .fill(tint.mix(with: .white, by: 0.5))
            .frame(width: edge.isVertical ? DockGeometry.indicatorSize : 16,
                   height: edge.isVertical ? 16 : DockGeometry.indicatorSize)
            .shadow(color: tint.opacity(0.9), radius: 3)
            .shadow(color: tint.opacity(0.5), radius: 7)
            .offset(drop)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct DockIceTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// Tint of the ice block behind the current dock item. Nil outside the Ice Blocks style,
    /// where items draw the configured running indicator instead.
    var dockIceTint: Color? {
        get { self[DockIceTintKey.self] }
        set { self[DockIceTintKey.self] = newValue }
    }
}
