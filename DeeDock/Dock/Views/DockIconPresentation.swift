import SwiftUI

/// Upright artwork with its running or selection marker on the physical outside edge.
struct DockIconPresentation: View {
    let icon: NSImage
    let size: CGFloat
    let edge: DockEdge
    let available: Bool
    let running: Bool
    let launching: Bool
    let selected: Bool

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
                .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    if launching {
                        Circle().fill(.black.opacity(0.14))
                        ProgressView().controlSize(.small).padding(8).glassEffect(.clear)
                    }
                }
                .position(iconCenter)
            if selected {
                RoundedRectangle(cornerRadius: 2).fill(.primary)
                    .frame(width: edge.isVertical ? DockGeometry.indicatorSize : 16,
                           height: edge.isVertical ? 16 : DockGeometry.indicatorSize)
                    .position(marker)
            } else {
                Circle().fill(.primary.opacity(running ? 0.8 : 0))
                    .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                    .frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
                    .position(marker)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }
}
