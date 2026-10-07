import CoreGraphics
import Testing
@testable import DeeDock

/// A tile's context menu must never overlap the tile, on any edge or screen arrangement.
struct DockContextMenuPlacementTests {
    private let menu = CGSize(width: 200, height: 300)
    private let clearance: CGFloat = 10

    /// The menu's frame in AppKit screen coordinates, from its top-left origin.
    private func frame(tile: CGRect, edge: DockEdge) -> CGRect {
        let origin = DockContextMenuPlacement.menuOrigin(tile: tile, menuSize: menu, edge: edge, clearance: clearance)
        return CGRect(x: origin.x, y: origin.y - menu.height, width: menu.width, height: menu.height)
    }

    @Test("The menu opens on the screen side of the tile, centered on it", arguments: DockEdge.allCases)
    func clearsTile(edge: DockEdge) {
        // A negative origin, as on a display left of or below the primary one.
        let tile = CGRect(x: -900, y: -400, width: 56, height: 60)
        let menuFrame = frame(tile: tile, edge: edge)

        #expect(!menuFrame.intersects(tile))
        switch edge {
        case .bottom:
            #expect(menuFrame.minY == tile.maxY + clearance)
            #expect(menuFrame.midX == tile.midX)
        case .top:
            #expect(menuFrame.maxY == tile.minY - clearance)
            #expect(menuFrame.midX == tile.midX)
        case .left:
            #expect(menuFrame.minX == tile.maxX + clearance)
            #expect(menuFrame.midY == tile.midY)
        case .right:
            #expect(menuFrame.maxX == tile.minX - clearance)
            #expect(menuFrame.midY == tile.midY)
        }
    }

    @Test("Clearance covers the spotlight's lift and growth")
    func clearanceCoversSpotlight() {
        let depth: CGFloat = 128
        let painted = DockContextMenuSpotlight.lift + depth * (DockContextMenuSpotlight.scale - 1)
        #expect(DockContextMenuPlacement.clearance(tileDepth: depth) > painted)
    }
}
