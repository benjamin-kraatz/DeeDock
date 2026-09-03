import SwiftUI

/// A 1440 by 900 desktop with a reserved bottom band and menu bar. All rectangles use production geometry.
struct DockDisplayDiagram: View {
    let settings: DockSettings
    let showsActivation: Bool
    private let scale: CGFloat = 0.22
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    var body: some View {
        let visible = CGRect(x: 0, y: 64, width: 1440, height: 812)
        let reference = DockGeometry.referenceFrame(screenFrame: screen, visibleFrame: visible, settings: settings)
        let layout = DockGeometry.layout(count: 6, favoriteCount: 3, availableLength: settings.edge.length(of: reference.size),
            availableDepth: settings.edge.depth(of: reference.size), settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
        let geometry = DockPresentationGeometry(screen: screen, restingFrame: frame, layout: layout, settings: settings.behavior)
        let glass = DockGeometry.restingGlass(frame: frame, layout: layout)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(.indigo.gradient)
            drawing(CGRect(x: 0, y: 0, width: 1440, height: 64)).fill(.black.opacity(0.18))
            drawing(CGRect(x: 0, y: 876, width: 1440, height: 24)).fill(.white.opacity(0.22))
            if showsActivation {
                drawing(geometry.activation.retention).fill(.white.opacity(0.10))
                drawing(geometry.activation.retention).stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                drawing(geometry.activation.zone).fill(.cyan)
            }
            drawing(glass).fill(.white.opacity(0.45))
            ForEach(layout.restingCenters.indices, id: \.self) { index in
                let rect = DockEdge.screenRect(layout.iconFrame(centerAlong: layout.restingCenters[index], size: layout.iconSize), in: frame)
                drawing(rect).fill([Color.blue, .cyan, .pink, .orange, .gray, .mint][index])
            }
        }
        .frame(width: screen.width * scale, height: screen.height * scale)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity).padding(.vertical, 6).accessibilityHidden(true)
    }

    private func drawing(_ rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX * scale, y: (screen.maxY - rect.maxY) * scale,
                    width: rect.width * scale, height: rect.height * scale))
    }
}
