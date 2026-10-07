import CoreGraphics
import Testing
@testable import DeeDock

/// A tile whose context menu is open must end up beside the menu, never under it.
struct DockContextMenuPlacementTests {
    private let menuSize = CGSize(width: 220, height: 300)
    /// A display left of and below the primary one, so every coordinate is negative.
    private let screen = CGRect(x: -1600, y: -1000, width: 1440, height: 900)

    /// A 56 × 60 tile flush against `edge`, at `along` points from the screen's leading or bottom side.
    private func tile(on edge: DockEdge, along: CGFloat) -> CGRect {
        let size = edge.isVertical ? CGSize(width: 60, height: 56) : CGSize(width: 56, height: 60)
        switch edge {
        case .bottom: return CGRect(origin: CGPoint(x: screen.minX + along, y: screen.minY + 8), size: size)
        case .top: return CGRect(origin: CGPoint(x: screen.minX + along, y: screen.maxY - 8 - size.height), size: size)
        case .left: return CGRect(origin: CGPoint(x: screen.minX + 8, y: screen.minY + along), size: size)
        case .right: return CGRect(origin: CGPoint(x: screen.maxX - 8 - size.width, y: screen.minY + along), size: size)
        }
    }

    @Test("The hopped tile clears the menu and the dock, wherever the click lands",
          arguments: DockEdge.allCases, [0.1, 0.5, 0.9])
    func clearsMenu(edge: DockEdge, pointerFraction: CGFloat) {
        // Near the start, middle, and end of the screen, so the menu opens both ways.
        let along = (edge.isVertical ? screen.height : screen.width) * pointerFraction
        let tile = tile(on: edge, along: along)
        // The leading quarter of the tile: the click that hid most of it behind the menu.
        let pointer = CGPoint(x: tile.minX + tile.width / 4, y: tile.maxY - tile.height / 4)
        let menu = DockContextMenuPlacement.predictedMenuFrame(pointer: pointer, menuSize: menuSize, screen: screen)
        let hopped = DockContextMenuPlacement.hoppedFrame(tile: tile, menu: menu, edge: edge)

        #expect(!hopped.intersects(menu))
        #expect(!hopped.intersects(tile))
        #expect(hopped.size == tile.size)
    }

    @Test("Menus hang right and down, and flip at the screen edges")
    func predictsMenuDirection() {
        let open = DockContextMenuPlacement.predictedMenuFrame(
            pointer: CGPoint(x: screen.midX, y: screen.midY), menuSize: menuSize, screen: screen)
        #expect(open.minX == screen.midX)
        #expect(open.maxY == screen.midY)

        let corner = DockContextMenuPlacement.predictedMenuFrame(
            pointer: CGPoint(x: screen.maxX - 10, y: screen.minY + 10), menuSize: menuSize, screen: screen)
        #expect(corner.maxX == screen.maxX - 10)
        #expect(corner.minY == screen.minY + 10)
    }

    @Test("The offset converts the screen move into SwiftUI's downward y")
    func offsetFlipsY() {
        let tile = CGRect(x: 100, y: 10, width: 50, height: 50)
        let offset = DockContextMenuPlacement.offset(from: tile, to: tile.offsetBy(dx: -30, dy: 60))
        #expect(offset == CGSize(width: -30, height: -60))
    }

    @Test("Clamping keeps a magnified tile inside the canvas without undoing its sideways move")
    func clampsToCanvas() {
        let canvas = CGRect(x: 0, y: 0, width: 800, height: 180)
        let magnified = CGRect(x: 300, y: 70, width: 96, height: 100)
        let clamped = DockContextMenuPlacement.clamp(CGSize(width: -60, height: -108), frame: magnified, within: canvas)
        #expect(clamped == CGSize(width: -60, height: -70))
        #expect(canvas.contains(magnified.offsetBy(dx: clamped.width, dy: clamped.height)))
    }
}
