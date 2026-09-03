import SwiftUI

/// An upright app-name label placed inward and clamped to the supplied visible callout region.
struct DockHoverLabel: View {
    let name: String
    let anchor: CGPoint
    let viewport: CGRect
    var edge: DockEdge = .bottom
    @State private var measuredSize = CGSize(width: 180, height: 30)

    private var maximumWidth: CGFloat { max(1, min(240, viewport.width - 16)) }
    private var center: CGPoint {
        let halfWidth = min(measuredSize.width, maximumWidth) / 2
        let halfHeight = min(measuredSize.height, viewport.height) / 2
        let requestedX: CGFloat = switch edge {
        case .bottom, .top: anchor.x
        case .left: viewport.minX + halfWidth + 8
        case .right: viewport.maxX - halfWidth - 8
        }
        return CGPoint(x: min(max(requestedX, viewport.minX + halfWidth + 8), viewport.maxX - halfWidth - 8),
                       y: min(max(anchor.y, viewport.minY + halfHeight), viewport.maxY - halfHeight))
    }

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: maximumWidth)
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: 7))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
            .position(center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
