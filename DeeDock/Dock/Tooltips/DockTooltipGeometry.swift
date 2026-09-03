import CoreGraphics

/// Upright tooltip placement in top-left viewport coordinates, independent of window origins and scale.
enum DockTooltipGeometry {
    static func frame(size: CGSize, icon: CGRect, dock: CGRect, region: CGRect,
                      edge: DockEdge, placement: DockTooltipPreset.Placement) -> CGRect {
        let bounds = region.insetBy(dx: min(8, region.width / 4), dy: min(2, region.height / 4))
        let size = CGSize(width: max(1, min(size.width, bounds.width)), height: max(1, min(size.height, bounds.height)))
        let anchor = placement == .dockCenter ? CGPoint(x: dock.midX, y: dock.midY) : CGPoint(x: icon.midX, y: icon.midY)
        var center: CGPoint
        switch edge {
        case .bottom: center = CGPoint(x: anchor.x, y: bounds.maxY - size.height / 2)
        case .top: center = CGPoint(x: anchor.x, y: bounds.minY + size.height / 2)
        case .left: center = CGPoint(x: bounds.minX + size.width / 2, y: anchor.y)
        case .right: center = CGPoint(x: bounds.maxX - size.width / 2, y: anchor.y)
        }
        if placement == .before || placement == .after {
            let delta = (edge.length(of: size) + edge.length(of: icon.size)) / 2 + 8
            let sign: CGFloat = placement == .before ? -1 : 1
            for direction in [sign, -sign] {
                let candidate = edge.along(center) + delta * direction
                let low = edge.along(bounds.origin) + edge.length(of: size) / 2
                let high = low + edge.length(of: bounds.size) - edge.length(of: size)
                if candidate >= low && candidate <= high {
                    if edge.isVertical { center.y = candidate } else { center.x = candidate }
                    break
                }
            }
        }
        center.x = min(max(center.x, bounds.minX + size.width / 2), bounds.maxX - size.width / 2)
        center.y = min(max(center.y, bounds.minY + size.height / 2), bounds.maxY - size.height / 2)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
