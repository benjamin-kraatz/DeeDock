import CoreGraphics

/// Where the Tuck rail sits beside a picker, and how big it is. Pure geometry in AppKit's screen
/// space (points, origin at the bottom-left of the primary display, y growing upward).
///
/// From the approved mockup (`docs/mockups/flix-pick.html`, style Tuck): a 58-point rail 8 points
/// to the right of the picker, its top 8 points below the picker's top, that opens to 272 points on
/// hover. When the open panel would leave the visible frame of the picker's display on the right,
/// it goes to the picker's left instead; the side is chosen with the open width, so opening never
/// makes it jump sides. When neither side has room, it overlaps the picker's edge inside the
/// visible frame. It is pushed up when it would reach below the visible frame (the Dock) and never
/// rises above it (the menu bar).
nonisolated enum FlixPickPlacement {
    static let railWidth: CGFloat = 58
    static let openWidth: CGFloat = 272
    static let gap: CGFloat = 8
    static let topInset: CGFloat = 8
    static let headerHeight: CGFloat = 50
    /// A row and the point between rows.
    static let rowPitch: CGFloat = 57
    static let listPadding: CGFloat = 12
    static let footerHeight: CGFloat = 28
    /// Transparent margin around the body for its shadow (as the Flix panel's).
    static let shadowMargin: CGFloat = FlixPanelGeometry.shadowMargin

    /// Which side of the picker the rail is on.
    enum Side: Sendable { case right, left }

    static func height(rows: Int, open: Bool) -> CGFloat {
        headerHeight + CGFloat(max(rows, 1)) * rowPitch + listPadding + (open ? footerHeight : 0)
    }

    /// Converts an Accessibility frame to AppKit's screen space.
    ///
    /// Accessibility measures from the top-left of the primary display (the one whose AppKit frame
    /// starts at 0, 0) with y growing downward; AppKit measures from that display's bottom-left
    /// with y growing upward. Both are in points on every display, so only y flips:
    /// `appKitY = primaryMaxY − axY − height`. Displays above or left of the primary have negative
    /// coordinates in both spaces, which the formula keeps.
    ///
    /// - Parameter primaryMaxY: `NSScreen.screens.first?.frame.maxY`, the primary display's height.
    static func appKitRect(fromAX rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    /// The side for a picker on a display, decided with the open width.
    static func side(picker: CGRect, visible: CGRect) -> Side {
        if picker.maxX + gap + openWidth <= visible.maxX { return .right }
        if picker.minX - gap - openWidth >= visible.minX { return .left }
        // Neither fits: the side with more room, overlapping the picker's edge.
        return visible.maxX - picker.maxX >= picker.minX - visible.minX ? .right : .left
    }

    /// The panel body beside `picker` (both in AppKit space) on `side`.
    static func body(picker: CGRect, visible: CGRect, rows: Int, open: Bool, side: Side) -> CGRect {
        let width = open ? openWidth : railWidth
        let height = min(self.height(rows: rows, open: open), visible.height)
        // The edge next to the picker stays put while the panel opens, so the rail never jumps.
        var x = side == .right ? picker.maxX + gap : picker.minX - gap - width
        let fullSpan = side == .right ? x + openWidth : x + width
        let fullStart = side == .right ? x : picker.minX - gap - openWidth
        if fullSpan > visible.maxX { x -= fullSpan - visible.maxX }
        if fullStart < visible.minX { x += visible.minX - fullStart }
        var top = picker.maxY - topInset
        top = min(top, visible.maxY)
        if top - height < visible.minY { top = visible.minY + height }
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// The window around a body: the body plus the shadow margin on every side.
    static func window(around body: CGRect) -> CGRect {
        body.insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }
}
