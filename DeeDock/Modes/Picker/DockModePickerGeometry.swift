import CoreGraphics

struct DockModePickerAnchor {
    let source: CGRect
    let edge: DockEdge
    let visibleFrame: CGRect
}

/// Places the keyboard picker inward from its source dock and clamps it to negative-origin displays.
nonisolated enum DockModePickerGeometry {
    static let margin: CGFloat = 12
    static let gap: CGFloat = 10

    static func frame(anchor: DockModePickerAnchor, modeCount: Int) -> CGRect {
        let available = anchor.visibleFrame.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(320, available.width),
                          height: min(CGFloat(max(1, min(modeCount, 7))) * 42 + 58, available.height))
        let proposed: CGPoint
        switch anchor.edge {
        case .bottom:
            proposed = CGPoint(x: anchor.source.midX - size.width / 2, y: anchor.source.maxY + gap)
        case .top:
            proposed = CGPoint(x: anchor.source.midX - size.width / 2, y: anchor.source.minY - size.height - gap)
        case .left:
            proposed = CGPoint(x: anchor.source.maxX + gap, y: anchor.source.midY - size.height / 2)
        case .right:
            proposed = CGPoint(x: anchor.source.minX - size.width - gap, y: anchor.source.midY - size.height / 2)
        }
        return CGRect(
            x: min(max(proposed.x, available.minX), available.maxX - size.width),
            y: min(max(proposed.y, available.minY), available.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}
