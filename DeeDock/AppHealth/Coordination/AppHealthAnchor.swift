import CoreGraphics

/// Where a labelling prompt attaches, in AppKit screen coordinates (origin at the lower-left of the primary
/// display, y up; secondary displays may have negative origins).
///
/// `DockCoordinator.appHealthAnchor(forBundleID:)` produces it with a fallback chain: the app's tile on a fully
/// shown dock (`tile`), else the primary display's shown dock (`dock`), else the main screen's lower-right corner
/// (`screen`).
struct AppHealthAnchor {
    let kind: AppHealthAnchorKind
    /// The tile, the dock surface, or, for `screen`, a zero-size point inset from the visible frame's lower-right
    /// corner.
    let rect: CGRect
    /// The dock's edge for `tile` and `dock`; nil for `screen`, where the prompt grows up and to the left of
    /// `rect`.
    let edge: DockEdge?
    /// The visible frame of the display the anchor is on, so the prompt stays clear of the menu bar and dock.
    let visibleFrame: CGRect

    /// The same anchor in the form `DockPopoverGeometry.placement(anchor:ideal:)` takes; nil for `screen`.
    var popoverAnchor: DockPopoverAnchor? {
        edge.map { DockPopoverAnchor(icon: rect, edge: $0, visibleFrame: visibleFrame) }
    }

    /// Inset of the `screen` anchor from the visible frame's corner.
    static let screenInset: CGFloat = 16

    /// The `screen` fallback for a display's visible frame.
    static func screen(visibleFrame: CGRect) -> AppHealthAnchor {
        let point = CGPoint(x: visibleFrame.maxX - screenInset, y: visibleFrame.minY + screenInset)
        return AppHealthAnchor(kind: .screen, rect: CGRect(origin: point, size: .zero), edge: nil,
                               visibleFrame: visibleFrame)
    }
}
