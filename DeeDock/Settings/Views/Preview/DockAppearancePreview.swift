import SwiftUI

/// Inert magnification and spacing sample on the selected physical edge.
struct DockAppearancePreview: View {
    var edge: DockEdge = .bottom
    let iconSize: Double
    let magnification: Double
    let itemSpacing: Double

    var appearanceSettings = DockSettings.defaults

    var body: some View {
        let settings = DockSettings(iconSize: iconSize, magnification: magnification, itemSpacing: itemSpacing, edge: edge)
        let layout = DockGeometry.layout(count: 6, favoriteCount: 6, availableLength: 1000, settings: settings)
        DockSampleView(layout: layout, magnified: true, appearanceSettings: appearanceSettings)
            .scaleEffect(0.5, anchor: .topLeading)
            .frame(width: layout.viewportSize.width * 0.5, height: layout.viewportSize.height * 0.5, alignment: .topLeading)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}

#if DEBUG
#Preview("Side appearance and spacing") {
    HStack {
        DockAppearancePreview(edge: .left, iconSize: 48, magnification: 1.4, itemSpacing: 4)
        DockAppearancePreview(edge: .right, iconSize: 96, magnification: 2, itemSpacing: 12)
    }.padding()
}
#endif
