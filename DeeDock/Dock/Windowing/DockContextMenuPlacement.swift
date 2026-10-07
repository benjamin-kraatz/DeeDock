import AppKit

/// Moves a dock tile out from under its own context menu.
///
/// Context menus open at the pointer, and near a screen edge AppKit opens them toward the screen,
/// so a right-click over a tile covers most of it. The menu keeps its native pointer placement; the
/// tile instead hops out of the dock to the side of the menu, so you can see what the menu is for.
/// All rectangles here are AppKit screen coordinates, where y grows upward.
enum DockContextMenuPlacement {
    /// Space between the hopped tile and the dock or menu, in points.
    static let gap: CGFloat = 8

    /// Where AppKit will open a context menu for a click at `pointer`.
    ///
    /// A context menu hangs right and down from the pointer, and opens left or up instead when the
    /// screen has no room on that side.
    static func predictedMenuFrame(pointer: CGPoint, menuSize: CGSize, screen: CGRect) -> CGRect {
        let x = pointer.x + menuSize.width <= screen.maxX ? pointer.x : pointer.x - menuSize.width
        let y = pointer.y - menuSize.height >= screen.minY ? pointer.y - menuSize.height : pointer.y
        return CGRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    }

    /// The tile's resting frame moved off the dock, toward the screen, beside the menu.
    ///
    /// The tile leaves the glass by `gap` and moves along the dock to whichever side of the menu
    /// it started on, so the two never overlap.
    static func hoppedFrame(tile: CGRect, menu: CGRect, edge: DockEdge) -> CGRect {
        var frame = tile
        switch edge {
        case .bottom: frame.origin.y = tile.maxY + gap
        case .top: frame.origin.y = tile.minY - gap - tile.height
        case .left: frame.origin.x = tile.maxX + gap
        case .right: frame.origin.x = tile.minX - gap - tile.width
        }
        if edge.isVertical {
            frame.origin.y = menu.midY <= tile.midY ? menu.maxY + gap : menu.minY - gap - tile.height
        } else {
            frame.origin.x = menu.midX >= tile.midX ? menu.minX - gap - tile.width : menu.maxX + gap
        }
        return frame
    }

    /// The SwiftUI offset (y grows downward) that carries `tile` to `hopped`.
    static func offset(from tile: CGRect, to hopped: CGRect) -> CGSize {
        CGSize(width: hopped.midX - tile.midX, height: tile.midY - hopped.midY)
    }

    /// Shortens `offset` so `frame` stays inside `bounds`, where the dock's content is clipped.
    ///
    /// A magnified tile has less room above it than its own size. It then stops short of clearing
    /// the glass, but keeps its sideways move, which is what keeps it out from under the menu.
    /// Both rectangles share one top-left coordinate space.
    static func clamp(_ offset: CGSize, frame: CGRect, within bounds: CGRect) -> CGSize {
        let moved = frame.offsetBy(dx: offset.width, dy: offset.height)
        var result = offset
        if moved.minX < bounds.minX { result.width += bounds.minX - moved.minX }
        else if moved.maxX > bounds.maxX { result.width -= moved.maxX - bounds.maxX }
        if moved.minY < bounds.minY { result.height += bounds.minY - moved.minY }
        else if moved.maxY > bounds.maxY { result.height -= moved.maxY - bounds.maxY }
        return result
    }
}

extension NSMenu {
    /// Opens this menu at the pointer for a dock tile, first publishing where the tile should go.
    ///
    /// Returns when tracking ends. The destination is published before the tile becomes the menu's
    /// owner. With Slide Out, the tile becomes the owner here and the menu waits
    /// ``DockContextMenuReveal/slideLead`` so the slide plays before the menu covers it.
    /// - Parameters:
    ///   - tile: The menu bridge view, which covers the tile's resting frame.
    ///   - interaction: The tile's dock; nil leaves the tile in place.
    ///   - event: The context click.
    ///   - beginTracking: Reports the menu as open. The delegate's `menuWillOpen` reports it again,
    ///     which owners must tolerate.
    @MainActor
    func popUpContextMenu(forDockTile tile: NSView, interaction: DockInteraction?, event: NSEvent,
                          beginTracking: () -> Void) {
        if let interaction, let window = tile.window, let screen = window.screen {
            let frame = window.convertToScreen(tile.convert(tile.bounds, to: nil))
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            let menu = DockContextMenuPlacement.predictedMenuFrame(pointer: pointer, menuSize: size,
                                                                  screen: screen.visibleFrame)
            let hopped = DockContextMenuPlacement.hoppedFrame(tile: frame, menu: menu, edge: interaction.layout.edge)
            interaction.contextMenuOffset = DockContextMenuPlacement.offset(from: frame, to: hopped)
            let reveal = interaction.contextMenuReveal.effective(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            if reveal == .slideOut {
                beginTracking()
                // Event-tracking mode keeps SwiftUI drawing and common-mode timers firing, but it
                // dispatches no events and no main-queue work, the same isolation NSMenu's own
                // tracking has. The click's mouse-up stays queued for the menu.
                let deadline = Date(timeIntervalSinceNow: DockContextMenuReveal.slideLead)
                while Date() < deadline {
                    RunLoop.current.run(mode: .eventTracking, before: deadline)
                }
            }
        }
        NSMenu.popUpContextMenu(self, with: event, for: tile)
    }
}
