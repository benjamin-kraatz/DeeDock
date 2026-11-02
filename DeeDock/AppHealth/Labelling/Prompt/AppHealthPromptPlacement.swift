import CoreGraphics

/// Where the prompt panel goes for an anchor.
///
/// Everything here is in AppKit screen coordinates: points, y up, origin at the lower-left corner of the primary
/// display, with displays to its left or below it at negative coordinates. `AppHealthAnchor` already arrives in
/// that space (the dock converted its tile from SwiftUI's flipped root space), and `NSWindow.setFrame` takes it
/// directly, so no conversion happens here. Backing scale is AppKit's concern.
enum AppHealthPromptPlacement {
    /// Space between the prompt and the tile or dock. `DockPopoverGeometry` leaves 2 pt because popovers draw
    /// their own pointer into that gap; the prompt has no pointer, so it keeps a little more distance.
    static let gap: CGFloat = 8

    /// The panel frame for content of `size`.
    ///
    /// `tile` and `dock` anchors use the dock popovers' placement (centred on the tile, inward from the dock's
    /// edge, clamped into the visible frame), pushed `gap` further from the dock. A `screen` anchor is a point
    /// near the visible frame's lower-right corner; the prompt grows up and to the left of it.
    static func frame(size: CGSize, anchor: AppHealthAnchor) -> CGRect {
        var frame: CGRect
        if let popover = anchor.popoverAnchor {
            frame = DockPopoverGeometry.placement(anchor: popover, ideal: size).frame
            switch popover.edge {
            case .bottom: frame.origin.y += gap
            case .top: frame.origin.y -= gap
            case .left: frame.origin.x += gap
            case .right: frame.origin.x -= gap
            }
        } else {
            frame = CGRect(x: anchor.rect.maxX - size.width, y: anchor.rect.minY,
                           width: size.width, height: size.height)
        }
        return clamp(frame, into: anchor.visibleFrame.insetBy(dx: DockPopoverGeometry.margin,
                                                              dy: DockPopoverGeometry.margin))
    }

    /// Moves `frame` inside `bounds` without resizing it; a frame larger than `bounds` keeps its top-left inside.
    static func clamp(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        var result = frame
        result.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
        result.origin.y = min(bounds.maxY - frame.height, max(frame.minY, bounds.minY))
        return result
    }
}
