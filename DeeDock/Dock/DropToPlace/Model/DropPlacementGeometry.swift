import CoreGraphics

/// How a Drop to Place target was chosen. The raw values double as analytics tokens.
nonisolated enum DropPlacementKind: String, Equatable, Sendable {
    /// Top-left corner at the pointer, shrunk and nudged to stay on screen.
    case free
    /// Snapped back to the app's remembered frame.
    case memory
    /// Left half of the usable frame.
    case left
    /// Right half of the usable frame.
    case right
    /// The whole usable frame.
    case fill
    /// Shift held: a rectangle drawn from the anchor to the pointer.
    case draw
}

/// One frame the ghost shows and the placement service applies.
nonisolated struct DropPlacementTarget: Equatable, Sendable {
    /// Global AppKit coordinates, in points.
    var frame: CGRect
    var kind: DropPlacementKind
    /// True when a free frame had to move away from the pointer to fit the usable frame.
    var nudged = false
}

/// Everything the target depends on. Pure values, so the model is testable without screens.
nonisolated struct DropPlacementInput: Sendable {
    /// The pointer in global AppKit coordinates (y grows upward).
    var pointer: CGPoint
    /// Usable frame of the display under the pointer: its visible frame minus the menu bar and
    /// any dock that reserves space. Global AppKit coordinates.
    var usable: CGRect
    /// The window size a free drop starts from. See ``DropPlacementGeometry/baseSize(running:remembered:usable:)``.
    var baseSize: CGSize
    /// The remembered frame, already resolved to a connected display, and that display's usable
    /// frame. Nil disables the magnet, as it is for running apps.
    var memory: (frame: CGRect, usable: CGRect)?
    /// Top-left corner fixed when Shift went down; nil while Shift is up.
    var drawAnchor: CGPoint?
}

/// The geometry behind Drop to Place, matching `target()` in `docs/mockups/drop-to-place.html`.
///
/// Every rectangle is in global AppKit coordinates: points, origin at the primary display's
/// lower-left corner, y growing upward, and negative origins for displays left of or below it.
/// A window's "top-left" is therefore `(minX, maxY)`. Conversion to the Quartz top-left space
/// used by Accessibility happens only at the AX boundary, in `DropPlacementService`.
nonisolated enum DropPlacementGeometry {
    /// Within this distance of the remembered frame's top-left corner the target snaps to it.
    static let magnetRadius: CGFloat = 44
    /// Pointer band along the usable frame's left, right, and top edges that tiles the window.
    static let edgeBand: CGFloat = 8
    /// Smallest frame a free drop shrinks to, and the smallest frame Shift can draw.
    static let minimumSize = CGSize(width: 320, height: 220)
    /// Size used when nothing is known about the app's windows.
    static let defaultSize = CGSize(width: 900, height: 600)
    /// The ghost springs out of a square this size, centered on the pointer.
    static let iconSide: CGFloat = 54
    /// Space kept between a reserving dock's glass and the usable frame.
    static let dockGap: CGFloat = 8

    /// The size a free drop starts from: the running window's, else the remembered frame's,
    /// else ``defaultSize``. Always clamped to the usable frame.
    static func baseSize(running: CGSize?, remembered: CGSize?, usable: CGRect) -> CGSize {
        let size = running ?? remembered ?? defaultSize
        return CGSize(width: min(size.width, usable.width), height: min(size.height, usable.height))
    }

    /// The Shift-draw anchor for a pointer: the pointer, held below the usable frame's top.
    static func drawAnchor(pointer: CGPoint, usable: CGRect) -> CGPoint {
        CGPoint(x: pointer.x, y: min(pointer.y, usable.maxY))
    }

    /// The square the ghost grows out of when Place arms.
    static func iconFrame(at pointer: CGPoint) -> CGRect {
        CGRect(x: pointer.x - iconSide / 2, y: pointer.y - iconSide / 2, width: iconSide, height: iconSide)
    }

    /// Chooses the target in the mockup's order: Shift draw, edge tiling, magnet, then free.
    static func target(_ input: DropPlacementInput) -> DropPlacementTarget {
        let pointer = input.pointer, usable = input.usable
        let minimum = CGSize(width: min(minimumSize.width, usable.width), height: min(minimumSize.height, usable.height))
        if let anchor = input.drawAnchor {
            // The anchor is the top-left corner; the pointer drags the bottom-right one.
            let width = max(minimum.width, min(pointer.x, usable.maxX) - anchor.x)
            let height = max(minimum.height, anchor.y - max(pointer.y, usable.minY))
            return DropPlacementTarget(frame: CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height),
                                       kind: .draw)
        }
        if pointer.x <= usable.minX + edgeBand {
            return DropPlacementTarget(frame: CGRect(x: usable.minX, y: usable.minY,
                                                     width: usable.width / 2, height: usable.height), kind: .left)
        }
        if pointer.x >= usable.maxX - edgeBand {
            return DropPlacementTarget(frame: CGRect(x: usable.midX, y: usable.minY,
                                                     width: usable.width / 2, height: usable.height), kind: .right)
        }
        // AppKit's top is maxY; the menu bar sits above it, so a pointer there also fills.
        if pointer.y >= usable.maxY - edgeBand {
            return DropPlacementTarget(frame: usable, kind: .fill)
        }
        if let memory = input.memory {
            let frame = clamp(memory.frame, into: memory.usable)
            if hypot(pointer.x - frame.minX, pointer.y - frame.maxY) < magnetRadius {
                return DropPlacementTarget(frame: frame, kind: .memory)
            }
        }
        let anchor = drawAnchor(pointer: pointer, usable: usable)
        var left = max(anchor.x, usable.minX), top = anchor.y
        var width = min(input.baseSize.width, usable.width), height = min(input.baseSize.height, usable.height)
        // Shrink toward the minimum first, then move: the corner stays under the pointer
        // for as long as the window can still fit.
        if left + width > usable.maxX { width = max(minimum.width, usable.maxX - left) }
        if left + width > usable.maxX { left = usable.maxX - width }
        if top - height < usable.minY { height = max(minimum.height, top - usable.minY) }
        if top - height < usable.minY { top = usable.minY + height }
        return DropPlacementTarget(frame: CGRect(x: left, y: top - height, width: width, height: height), kind: .free,
                                   nudged: left != anchor.x || top != anchor.y)
    }

    /// Fits `frame` inside `usable`: shrinks it to at most the usable size, then shifts it in.
    static func clamp(_ frame: CGRect, into usable: CGRect) -> CGRect {
        let width = min(frame.width, usable.width), height = min(frame.height, usable.height)
        let x = min(max(frame.minX, usable.minX), usable.maxX - width)
        let y = min(max(frame.minY, usable.minY), usable.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The part of a display's visible frame not covered by docks that keep their space.
    ///
    /// `visible` is `NSScreen.visibleFrame` (already without the menu bar and the macOS Dock).
    /// Each rectangle in `docks` is a dock's resting glass. A dock is trimmed from the side it
    /// is closest to, plus ``dockGap``. Auto-hiding docks must not be passed in.
    static func usableFrame(visible: CGRect, docks: [CGRect]) -> CGRect {
        var result = visible
        for dock in docks where dock.intersects(visible) {
            let gaps: [(CGFloat, Int)] = [(dock.minY - visible.minY, 0), (visible.maxY - dock.maxY, 1),
                                          (dock.minX - visible.minX, 2), (visible.maxX - dock.maxX, 3)]
            switch gaps.min(by: { $0.0 < $1.0 })?.1 {
            case 0:
                let bottom = max(result.minY, dock.maxY + dockGap)
                result = CGRect(x: result.minX, y: bottom, width: result.width, height: max(0, result.maxY - bottom))
            case 1:
                let top = min(result.maxY, dock.minY - dockGap)
                result = CGRect(x: result.minX, y: result.minY, width: result.width, height: max(0, top - result.minY))
            case 2:
                let left = max(result.minX, dock.maxX + dockGap)
                result = CGRect(x: left, y: result.minY, width: max(0, result.maxX - left), height: result.height)
            default:
                let right = min(result.maxX, dock.minX - dockGap)
                result = CGRect(x: result.minX, y: result.minY, width: max(0, right - result.minX), height: result.height)
            }
        }
        return result
    }
}
