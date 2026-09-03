import CoreGraphics

/// Physical screen edge, independent of language direction and display-array order.
enum DockEdge: String, Codable, CaseIterable {
    case bottom, top, left, right

    var isVertical: Bool { self == .left || self == .right }

    /// Extracts distance along the ordered axis in top-left coordinates.
    func along(_ point: CGPoint) -> CGFloat { isVertical ? point.y : point.x }
    func length(of size: CGSize) -> CGFloat { isVertical ? size.height : size.width }
    func depth(of size: CGSize) -> CGFloat { isVertical ? size.width : size.height }
    func size(length: CGFloat, depth: CGFloat) -> CGSize {
        isVertical ? CGSize(width: depth, height: length) : CGSize(width: length, height: depth)
    }

    /// Canonical coordinates describe a bottom dock: x follows item order and y points outward.
    /// Transform geometry only. Icons and text remain upright on every edge.
    func point(_ point: CGPoint, depth: CGFloat) -> CGPoint {
        switch self {
        case .bottom: point
        case .top: CGPoint(x: point.x, y: depth - point.y)
        case .left: CGPoint(x: depth - point.y, y: point.x)
        case .right: CGPoint(x: point.y, y: point.x)
        }
    }

    func canonical(_ point: CGPoint, depth: CGFloat) -> CGPoint {
        switch self {
        case .bottom: point
        case .top: CGPoint(x: point.x, y: depth - point.y)
        case .left: CGPoint(x: point.y, y: depth - point.x)
        case .right: CGPoint(x: point.y, y: point.x)
        }
    }

    func rect(_ rect: CGRect, depth: CGFloat) -> CGRect {
        guard !rect.isNull else { return .null }
        let a = point(rect.origin, depth: depth)
        let b = point(CGPoint(x: rect.maxX, y: rect.maxY), depth: depth)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func offset(_ offset: CGSize) -> CGSize {
        switch self {
        case .bottom: offset
        case .top: CGSize(width: offset.width, height: -offset.height)
        case .left: CGSize(width: -offset.height, height: offset.width)
        case .right: CGSize(width: offset.height, height: offset.width)
        }
    }

    /// Only arrows parallel to the dock navigate or reorder. Values are native macOS key codes.
    func navigationStep(keyCode: UInt16) -> Int? {
        if keyCode == (isVertical ? 126 : 123) { return -1 }
        if keyCode == (isVertical ? 125 : 124) { return 1 }
        return nil
    }

    /// Converts top-left content bounds to a global AppKit rectangle, preserving negative origins.
    static func screenRect(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
