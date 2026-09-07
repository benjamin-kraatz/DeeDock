import Foundation
import CoreGraphics

/// All rectangles are AppKit screen points, including negative display origins.
enum LauncherGeometry {
    static func frame(visibleFrame: CGRect, origin: CGRect, edge: DockEdge) -> CGRect {
        let usable = visibleFrame.insetBy(dx: min(24, visibleFrame.width * 0.04), dy: min(24, visibleFrame.height * 0.04))
        let size = CGSize(width: min(960, usable.width), height: min(720, usable.height))
        var x = origin.midX - size.width / 2, y = origin.midY - size.height / 2
        switch edge {
        case .bottom: y = origin.minY
        case .top: y = origin.maxY - size.height
        case .left: x = origin.minX
        case .right: x = origin.maxX - size.width
        }
        return CGRect(x: min(max(x, usable.minX), usable.maxX - size.width),
                      y: min(max(y, usable.minY), usable.maxY - size.height), width: size.width, height: size.height)
    }
}
