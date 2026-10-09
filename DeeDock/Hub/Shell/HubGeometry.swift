import CoreGraphics

/// The DOKK tile an anchored Hub points at, in AppKit screen coordinates (origin at the lower left
/// of the primary display, y up).
///
/// `tile` is the tile's *resting* frame, before magnification. The live frame grows and shifts
/// while the pointer is over the dock and settles once the Hub takes the pointer away, so aiming at
/// the resting frame keeps the pointer from drifting during the open animation.
struct HubAnchor: Equatable {
    /// The resting DOKK tile.
    var tile: CGRect
    /// The screen edge the dock sits on. The Hub opens away from it.
    var edge: DockEdge
    /// The visible frame of the tile's display. The Hub stays inside it, inset by
    /// ``HubStyle/screenMargin``.
    var visibleFrame: CGRect
}

/// Where an anchored Hub sits and where its pointer aims.
struct HubAnchoredPlacement: Equatable {
    /// The glass body without the pointer, in AppKit screen coordinates.
    var body: CGRect
    /// The dock edge; the pointer sits on the body's side that faces it.
    var edge: DockEdge
    /// Center of the pointer along the side facing the dock, measured in the body's top-left,
    /// y-down space: an x offset for top and bottom docks, a y offset for left and right ones.
    var pointerOffset: CGFloat
}

/// Pure placement for the anchored Hub. Every input and output is in AppKit screen coordinates,
/// so displays left of or below the primary one (negative origins) need no special case.
enum HubGeometry {
    /// Keeps the pointer clear of the body's rounded corners.
    static var pointerInset: CGFloat { HubStyle.anchoredCornerRadius + HubStyle.pointerSize.width / 2 }

    /// Places the Hub beside `anchor` on the side away from the dock.
    ///
    /// The body is ``HubStyle/anchoredSize`` clamped to the visible frame minus
    /// ``HubStyle/screenMargin`` on every side. Along the dock it centers on the tile and then
    /// slides to stay on screen; across the dock it starts ``HubStyle/anchorGap`` plus the pointer
    /// depth past the tile, so the pointer tip ends `anchorGap` from the tile. The pointer offset
    /// follows the tile's center, clamped so it never runs into a rounded corner.
    static func anchoredPlacement(anchor: HubAnchor, ideal: CGSize = HubStyle.anchoredSize) -> HubAnchoredPlacement {
        let margin = HubStyle.screenMargin
        let reach = HubStyle.anchorGap + HubStyle.pointerSize.height
        let visible = anchor.visibleFrame
        let tile = anchor.tile
        let available = visible.insetBy(dx: margin, dy: margin)

        // Room across the dock: from the pointer's base to the far side of the visible frame.
        // When the tile lies outside the visible frame (a dock in the system Dock's reserved
        // area), the near side is still bounded by the visible frame.
        let body: CGRect
        switch anchor.edge {
        case .bottom, .top:
            let width = min(ideal.width, available.width)
            let near = anchor.edge == .bottom
                ? max(tile.maxY + reach, available.minY)
                : min(tile.minY - reach, available.maxY)
            let room = anchor.edge == .bottom ? available.maxY - near : near - available.minY
            let height = min(ideal.height, max(0, room))
            let x = clamp(tile.midX - width / 2, lower: available.minX, upper: available.maxX - width)
            let y = anchor.edge == .bottom ? near : near - height
            body = CGRect(x: x, y: y, width: width, height: height)
        case .left, .right:
            let height = min(ideal.height, available.height)
            let near = anchor.edge == .left
                ? max(tile.maxX + reach, available.minX)
                : min(tile.minX - reach, available.maxX)
            let room = anchor.edge == .left ? available.maxX - near : near - available.minX
            let width = min(ideal.width, max(0, room))
            let y = clamp(tile.midY - height / 2, lower: available.minY, upper: available.maxY - height)
            let x = anchor.edge == .left ? near : near - width
            body = CGRect(x: x, y: y, width: width, height: height)
        }

        // Screen space is y-up; the offset is measured from the body's top edge for side docks.
        let raw: CGFloat
        let length: CGFloat
        switch anchor.edge {
        case .bottom, .top:
            raw = tile.midX - body.minX
            length = body.width
        case .left, .right:
            raw = body.maxY - tile.midY
            length = body.height
        }
        let inset = min(pointerInset, length / 2)
        let offset = clamp(raw, lower: inset, upper: length - inset)
        return HubAnchoredPlacement(body: body, edge: anchor.edge, pointerOffset: offset)
    }

    /// The pointer tip in screen coordinates: the open animation scales toward it.
    static func pointerTip(of placement: HubAnchoredPlacement) -> CGPoint {
        let body = placement.body
        let depth = HubStyle.pointerSize.height
        switch placement.edge {
        case .bottom: return CGPoint(x: body.minX + placement.pointerOffset, y: body.minY - depth)
        case .top: return CGPoint(x: body.minX + placement.pointerOffset, y: body.maxY + depth)
        case .left: return CGPoint(x: body.minX - depth, y: body.maxY - placement.pointerOffset)
        case .right: return CGPoint(x: body.maxX + depth, y: body.maxY - placement.pointerOffset)
        }
    }

    /// A remembered detached frame, kept on a display that still exists.
    ///
    /// Returns `frame` resized to at least ``HubStyle/minimumDetachedSize`` and to at most the
    /// visible frame it overlaps most, then moved fully inside that frame. When it overlaps no
    /// visible frame (its display was unplugged), it centers on `fallback`.
    static func restoredDetachedFrame(_ frame: CGRect, visibleFrames: [CGRect], fallback: CGRect) -> CGRect {
        var host: CGRect?
        var bestArea: CGFloat = 0
        for visible in visibleFrames {
            let overlap = visible.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                host = visible
            }
        }
        let target = host ?? fallback
        let minimum = HubStyle.minimumDetachedSize
        let size = CGSize(width: min(max(frame.width, minimum.width), target.width),
                          height: min(max(frame.height, minimum.height), target.height))
        let origin = host == nil
            ? CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
            : CGPoint(x: clamp(frame.minX, lower: target.minX, upper: target.maxX - size.width),
                      y: clamp(frame.minY, lower: target.minY, upper: target.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// The first detached frame: the anchored body's size, centered on the visible frame.
    static func initialDetachedFrame(from body: CGRect, visibleFrame: CGRect) -> CGRect {
        let minimum = HubStyle.minimumDetachedSize
        let size = CGSize(width: min(max(body.width, minimum.width), visibleFrame.width),
                          height: min(max(body.height, minimum.height), visibleFrame.height))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Clamps without trapping when `upper < lower`; the lower bound wins, keeping the leading
    /// (or bottom) edge on screen.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
