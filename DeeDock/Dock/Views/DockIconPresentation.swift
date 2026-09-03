import SwiftUI

/// Upright artwork with a running-state decoration and an independent keyboard-selection outline.
struct DockIconPresentation: View {
    let icon: NSImage
    let size: CGFloat
    let edge: DockEdge
    let available: Bool
    let running: Bool
    let launching: Bool
    let keyboardSelected: Bool
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot

    /// Applied only to artwork, preserving focus/launch feedback and the button hit region.
    var artworkOpacity: Double = 1
    var artworkAnimation: Animation? = nil

    var body: some View {
        let depth = size + DockGeometry.indicatorAreaDepth
        let bounds = edge.size(length: size, depth: depth)
        let iconCenter = edge.point(CGPoint(x: size / 2, y: size / 2), depth: depth)
        let marker = edge.point(CGPoint(x: size / 2,
            y: size + DockGeometry.indicatorSpacing + DockGeometry.indicatorSize / 2), depth: depth)
        ZStack(alignment: .topLeading) {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .opacity(available ? 1 : 0.4)
                .modifier(DockIconIndicator(style: runningIndicatorStyle, running: running, size: size))
                .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                .overlay {
                    if keyboardSelected {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    if launching {
                        Circle().fill(.black.opacity(0.14))
                        ProgressView().controlSize(.small).padding(8).glassEffect(.clear)
                    }
                }
                .position(iconCenter)
            if running {
                DockRunningIndicator(style: runningIndicatorStyle, edge: edge)
                    .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                    .position(marker)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }
}
