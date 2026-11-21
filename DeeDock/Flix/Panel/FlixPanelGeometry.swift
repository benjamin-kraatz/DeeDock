import CoreGraphics

/// Where the Flix panel goes, in AppKit screen coordinates (origin bottom left, y up). Pure, so the
/// placement rules are testable.
///
/// The window is the panel body plus ``shadowMargin`` on every side, transparent, so the drawn
/// shadow is never clipped. All frames are clamped into the display's visible frame, which handles
/// displays with negative origins the same as the primary one.
nonisolated enum FlixPanelGeometry {
    static let idealSize = CGSize(width: 700, height: 548)
    static let minimumSize = CGSize(width: 520, height: 360)
    static let shadowMargin: CGFloat = 30
    /// Space between the tile and the panel.
    static let tileGap: CGFloat = 12
    static let screenInset: CGFloat = 8

    /// The body size that fits `visibleFrame`.
    static func size(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(idealSize.width, max(minimumSize.width, visibleFrame.width - screenInset * 2)),
               height: min(idealSize.height, max(minimumSize.height, visibleFrame.height - screenInset * 2)))
    }

    /// Above a bottom dock's tile, below a top one, beside a side one; centered on the tile.
    /// - Returns: The body frame and the unit point (top-left origin) the open animation grows from.
    static func anchored(tile: CGRect, edge: DockEdge, visibleFrame: CGRect) -> (body: CGRect, growth: FlixGrowthAnchor) {
        let size = size(in: visibleFrame)
        var origin: CGPoint
        switch edge {
        case .bottom: origin = CGPoint(x: tile.midX - size.width / 2, y: tile.maxY + tileGap)
        case .top: origin = CGPoint(x: tile.midX - size.width / 2, y: tile.minY - tileGap - size.height)
        case .left: origin = CGPoint(x: tile.maxX + tileGap, y: tile.midY - size.height / 2)
        case .right: origin = CGPoint(x: tile.minX - tileGap - size.width, y: tile.midY - size.height / 2)
        }
        let body = clamp(CGRect(origin: origin, size: size), into: visibleFrame)
        return (body, growth(toward: CGPoint(x: tile.midX, y: tile.midY), in: body))
    }

    /// Near the pointer: its top-left corner a little up and left of it, like a context menu that
    /// leaves the pointer over the first rows.
    static func atPointer(_ pointer: CGPoint, visibleFrame: CGRect) -> (body: CGRect, growth: FlixGrowthAnchor) {
        let size = size(in: visibleFrame)
        let origin = CGPoint(x: pointer.x - 60, y: pointer.y + 80 - size.height)
        let body = clamp(CGRect(origin: origin, size: size), into: visibleFrame)
        return (body, growth(toward: pointer, in: body))
    }

    /// The window frame around a body frame.
    static func window(around body: CGRect) -> CGRect {
        body.insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }

    static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: screenInset, dy: screenInset)
        var frame = frame
        frame.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        frame.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
        return frame
    }

    /// `point` as a unit point of `body`, top-left origin, clamped to the body's edges.
    static func growth(toward point: CGPoint, in body: CGRect) -> FlixGrowthAnchor {
        guard body.width > 0, body.height > 0 else { return FlixGrowthAnchor(x: 0.5, y: 0.5) }
        let x = (point.x - body.minX) / body.width
        let y = (body.maxY - point.y) / body.height
        return FlixGrowthAnchor(x: min(max(0, x), 1), y: min(max(0, y), 1))
    }
}
