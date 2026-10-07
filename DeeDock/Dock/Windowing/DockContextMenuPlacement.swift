import AppKit

/// Places a dock tile's context menu beside the tile instead of at the pointer.
///
/// A pointer-anchored menu near the screen edge opens toward the screen from the click and covers
/// the tile it belongs to. Like the system Dock, this centers the menu on the tile, on the screen
/// side of the dock, so the spotlighted tile stays visible while the menu is open.
enum DockContextMenuPlacement {
    /// Space between the spotlighted tile's painted extent and the menu, in points.
    static let gap: CGFloat = 6

    /// The menu's top-left corner in AppKit screen coordinates (y grows upward).
    ///
    /// - Parameters:
    ///   - tile: The tile's resting frame in screen coordinates, including its indicator strip.
    ///   - menuSize: The menu's size before it opens.
    ///   - edge: The screen edge the dock sits on.
    ///   - clearance: Distance kept between the tile's resting frame and the menu.
    /// AppKit still shifts the menu along the dock when it would cross a screen edge.
    static func menuOrigin(tile: CGRect, menuSize: CGSize, edge: DockEdge, clearance: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: tile.midX - menuSize.width / 2, y: tile.maxY + clearance + menuSize.height)
        case .top: CGPoint(x: tile.midX - menuSize.width / 2, y: tile.minY - clearance)
        case .left: CGPoint(x: tile.maxX + clearance, y: tile.midY + menuSize.height / 2)
        case .right: CGPoint(x: tile.minX - clearance - menuSize.width, y: tile.midY + menuSize.height / 2)
        }
    }

    /// Clears the tile's spotlight lift and growth, which extend past its resting frame.
    static func clearance(tileDepth: CGFloat) -> CGFloat {
        gap + DockContextMenuSpotlight.lift + tileDepth * (DockContextMenuSpotlight.scale - 1)
    }
}

extension NSMenu {
    /// Opens this menu beside a dock tile and returns when tracking ends.
    ///
    /// Falls back to the pointer location when the tile has no window or the dock edge is unknown.
    /// - Parameters:
    ///   - tile: The menu bridge view, which covers the tile's resting frame.
    ///   - edge: The screen edge of the tile's dock.
    ///   - event: The context click, used only by the fallback.
    @MainActor
    func popUp(besideDockTile tile: NSView, edge: DockEdge?, event: NSEvent) {
        guard let edge, let window = tile.window else {
            NSMenu.popUpContextMenu(self, with: event, for: tile)
            return
        }
        let frame = window.convertToScreen(tile.convert(tile.bounds, to: nil))
        let origin = DockContextMenuPlacement.menuOrigin(
            tile: frame,
            menuSize: size,
            edge: edge,
            clearance: DockContextMenuPlacement.clearance(tileDepth: edge.depth(of: frame.size))
        )
        popUp(positioning: nil, at: origin, in: nil)
    }
}
