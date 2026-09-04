import CoreGraphics

/// The dock tile a popover attaches to, in AppKit screen coordinates.
struct DockPopoverAnchor {
    let icon: CGRect
    let edge: DockEdge
    let visibleFrame: CGRect
}

nonisolated struct DockPopoverChrome: Equatable, Sendable {
    let edge: DockEdge
    /// Attachment coordinate in the panel's top-left local coordinate space.
    let attachment: CGFloat
}

nonisolated struct DockPopoverPlacement: Equatable, Sendable {
    let frame: CGRect
    let chrome: DockPopoverChrome
}

/// Pure screen-space placement shared by every transient panel anchored to a dock tile.
nonisolated enum DockPopoverGeometry {
    static let margin: CGFloat = 16
    static let idealSize = CGSize(width: 560, height: 420)
    static let minimumSize = CGSize(width: 280, height: 220)
    static let attachmentGap: CGFloat = 2
    static let pointerDepth: CGFloat = 10

    static func frame(anchor: DockPopoverAnchor) -> CGRect {
        placement(anchor: anchor).frame
    }

    static func placement(anchor: DockPopoverAnchor, ideal: CGSize = idealSize) -> DockPopoverPlacement {
        let available = anchor.visibleFrame.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(ideal.width, max(minimumSize.width, available.width)),
                          height: min(ideal.height, max(minimumSize.height, available.height)))
        var origin: CGPoint
        switch anchor.edge {
        case .bottom: origin = CGPoint(x: anchor.icon.midX - size.width / 2, y: anchor.icon.maxY + attachmentGap)
        case .top: origin = CGPoint(x: anchor.icon.midX - size.width / 2, y: anchor.icon.minY - size.height - attachmentGap)
        case .left: origin = CGPoint(x: anchor.icon.maxX + attachmentGap, y: anchor.icon.midY - size.height / 2)
        case .right: origin = CGPoint(x: anchor.icon.minX - size.width - attachmentGap, y: anchor.icon.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, available.minX), available.maxX - size.width)
        origin.y = min(max(origin.y, available.minY), available.maxY - size.height)
        let frame = CGRect(origin: origin, size: size)
        let vertical: Bool
        switch anchor.edge {
        case .left, .right: vertical = true
        case .bottom, .top: vertical = false
        }
        let rawAttachment = vertical
            ? frame.maxY - anchor.icon.midY
            : anchor.icon.midX - frame.minX
        let length = vertical ? size.height : size.width
        let attachment = min(max(28, rawAttachment), max(28, length - 28))
        return DockPopoverPlacement(frame: frame, chrome: DockPopoverChrome(edge: anchor.edge, attachment: attachment))
    }

    static func dismissedFrame(from frame: CGRect, edge: DockEdge) -> CGRect {
        let distance: CGFloat = 10
        switch edge {
        case .bottom: return frame.offsetBy(dx: 0, dy: -distance)
        case .top: return frame.offsetBy(dx: 0, dy: distance)
        case .left: return frame.offsetBy(dx: -distance, dy: 0)
        case .right: return frame.offsetBy(dx: distance, dy: 0)
        }
    }
}
