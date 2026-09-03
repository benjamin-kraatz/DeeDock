import SwiftUI

/// An inert 1440×900 desktop diagram uses production placement and activation geometry.
struct DockZoneDiagram: View {
    let settings: DockSettings
    private let scale: CGFloat = 0.22
    var body: some View {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 64, width: 1440, height: 812)
        let reference = DockGeometry.referenceFrame(screenFrame: screen, visibleFrame: visible, settings: settings)
        let layout = DockGeometry.layout(count: 6, favoriteCount: 3, availableWidth: reference.width, settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
        let geometry = DockPresentationGeometry(screen: screen, restingFrame: frame, layout: layout, settings: settings.behavior)
        let width = min(layout.viewportWidth, layout.contentWidth(sizes: Array(repeating: layout.iconSize, count: 6)))
        let glass = CGRect(x: frame.midX - width / 2, y: frame.minY + DockGeometry.bottomMargin, width: width, height: layout.iconSize + 36)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(.indigo.gradient)
                drawing(geometry.activation.retention).fill(.white.opacity(0.10))
                drawing(geometry.activation.retention).stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                drawing(glass).fill(.white.opacity(0.6))
                drawing(geometry.activation.zone).fill(.cyan)
            }
            .frame(width: screen.width * scale, height: screen.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(.behaviorDiagramLegend).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func drawing(_ rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX * scale, y: (900 - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale))
    }
}
