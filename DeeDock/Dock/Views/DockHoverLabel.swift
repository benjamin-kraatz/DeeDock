import SwiftUI

/// A system-provided app name kept within the visible viewport, even in a scrolling dock.
struct DockHoverLabel: View {
    let name: String
    /// Desired label center in top-left canvas coordinates.
    let anchor: CGPoint
    let viewport: CGRect
    @State private var measuredWidth: CGFloat = 180

    private var maximumWidth: CGFloat { max(1, min(240, viewport.width - 16)) }
    private var centerX: CGFloat {
        let halfWidth = min(measuredWidth, maximumWidth) / 2
        return min(max(anchor.x, viewport.minX + halfWidth + 8), viewport.maxX - halfWidth - 8)
    }

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: maximumWidth)
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: 7))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
            .position(x: centerX, y: anchor.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
