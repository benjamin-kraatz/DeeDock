import CoreGraphics
import Testing
@testable import DeeDock

/// Drop to Place geometry in global AppKit coordinates (y up). The window's top-left is (minX, maxY).
struct DropPlacementGeometryTests {
    /// A 1440 × 900 primary display with a 25 pt menu bar and a bottom dock reserving 80 pt.
    private let usable = CGRect(x: 0, y: 80, width: 1440, height: 795)
    private let base = CGSize(width: 900, height: 600)

    private func target(_ pointer: CGPoint, usable: CGRect? = nil, base: CGSize? = nil,
                        memory: (CGRect, CGRect)? = nil, anchor: CGPoint? = nil) -> DropPlacementTarget {
        DropPlacementGeometry.target(.init(pointer: pointer, usable: usable ?? self.usable, baseSize: base ?? self.base,
                                           memory: memory.map { (frame: $0.0, usable: $0.1) }, drawAnchor: anchor))
    }

    // MARK: Zones

    @Test("Zones: reorder under 64 pt, Unpin from 64, Place from 180 pt")
    func zones() {
        #expect(DockDragZone.resolve(distance: 63.9, overDock: false, isPinned: true, canPlace: true) == .near)
        #expect(DockDragZone.resolve(distance: 64, overDock: false, isPinned: true, canPlace: true) == .unpin)
        #expect(DockDragZone.resolve(distance: 179.9, overDock: false, isPinned: true, canPlace: true) == .unpin)
        #expect(DockDragZone.resolve(distance: 180, overDock: false, isPinned: true, canPlace: true) == .place)
        #expect(DockDragGeometry.placeDistance == 180)
    }

    @Test("Running-only tiles do nothing in the Unpin band and place beyond it")
    func runningOnly() {
        #expect(DockDragZone.resolve(distance: 100, overDock: false, isPinned: false, canPlace: true) == .inert)
        #expect(DockDragZone.resolve(distance: 400, overDock: false, isPinned: false, canPlace: true) == .place)
    }

    @Test("Folders keep unpinning at any distance; any dock under the pointer protects the drag")
    func foldersAndDocks() {
        #expect(DockDragZone.resolve(distance: 900, overDock: false, isPinned: true, canPlace: false) == .unpin)
        #expect(DockDragZone.resolve(distance: 900, overDock: true, isPinned: true, canPlace: true) == .near)
    }

    // MARK: Free placement

    @Test("Free: the top-left corner sits at the pointer with the base size")
    func free() {
        let result = target(CGPoint(x: 200, y: 700))
        #expect(result.kind == .free)
        #expect(result.frame == CGRect(x: 200, y: 100, width: 900, height: 600))
        #expect(!result.nudged)
    }

    @Test("Free: overflowing right shrinks the width, then shifts at the minimum")
    func fitRight() {
        let shrunk = target(CGPoint(x: 1000, y: 700))
        #expect(shrunk.frame == CGRect(x: 1000, y: 100, width: 440, height: 600))
        #expect(!shrunk.nudged)
        let shifted = target(CGPoint(x: 1300, y: 700))
        #expect(shifted.frame.width == DropPlacementGeometry.minimumSize.width)
        #expect(shifted.frame.maxX == usable.maxX)
        #expect(shifted.nudged)
    }

    @Test("Free: overflowing the bottom shrinks the height, then lifts the window at the minimum")
    func fitBottom() {
        let shrunk = target(CGPoint(x: 200, y: 400))
        #expect(shrunk.frame == CGRect(x: 200, y: 80, width: 900, height: 320))
        let lifted = target(CGPoint(x: 200, y: 200))
        #expect(lifted.frame == CGRect(x: 200, y: 80, width: 900, height: 220))
        #expect(lifted.nudged)
    }

    @Test("Base size prefers the running window, then the remembered frame, and is clamped to the screen")
    func baseSize() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        #expect(DropPlacementGeometry.baseSize(running: CGSize(width: 400, height: 300), remembered: CGSize(width: 700, height: 400),
                                               usable: usable) == CGSize(width: 400, height: 300))
        #expect(DropPlacementGeometry.baseSize(running: nil, remembered: CGSize(width: 700, height: 400), usable: usable)
                == CGSize(width: 700, height: 400))
        #expect(DropPlacementGeometry.baseSize(running: nil, remembered: nil, usable: small) == CGSize(width: 800, height: 500))
    }

    // MARK: Magnet

    @Test("Magnet: within 44 pt of the remembered top-left corner snaps to that frame")
    func magnet() {
        let remembered = CGRect(x: 600, y: 300, width: 500, height: 400) // top-left (600, 700)
        let near = target(CGPoint(x: 630, y: 680), memory: (remembered, usable))
        #expect(near.kind == .memory)
        #expect(near.frame == remembered)
        let far = target(CGPoint(x: 600 + 44, y: 700), memory: (remembered, usable))
        #expect(far.kind == .free)
        #expect(target(CGPoint(x: 630, y: 680)).kind == .free)
    }

    @Test("Magnet: a remembered frame partly off its display is clamped back onto it")
    func magnetClamp() {
        let remembered = CGRect(x: 1200, y: 500, width: 500, height: 400)
        let result = target(CGPoint(x: 950, y: 860), memory: (remembered, usable))
        #expect(result.kind == .memory)
        #expect(result.frame == CGRect(x: 940, y: 475, width: 500, height: 400))
    }

    // MARK: Edge tiling

    @Test("Tiling: 8 pt bands at the left, right, and top edges")
    func tiling() {
        #expect(target(CGPoint(x: 8, y: 400)).frame == CGRect(x: 0, y: 80, width: 720, height: 795))
        #expect(target(CGPoint(x: 8, y: 400)).kind == .left)
        #expect(target(CGPoint(x: 9, y: 400)).kind == .free)
        #expect(target(CGPoint(x: 1432, y: 400)).frame == CGRect(x: 720, y: 80, width: 720, height: 795))
        #expect(target(CGPoint(x: 1432, y: 400)).kind == .right)
        #expect(target(CGPoint(x: 700, y: 867)).kind == .fill)
        #expect(target(CGPoint(x: 700, y: 890)).frame == usable)
        #expect(target(CGPoint(x: 700, y: 866)).kind == .free)
    }

    @Test("Tiling wins over the magnet")
    func tilingBeforeMagnet() {
        let remembered = CGRect(x: 0, y: 300, width: 500, height: 400)
        #expect(target(CGPoint(x: 4, y: 700), memory: (remembered, usable)).kind == .left)
    }

    // MARK: Shift draw

    @Test("Shift draws from the anchor to the pointer, at least 320 × 220")
    func draw() {
        let anchor = DropPlacementGeometry.drawAnchor(pointer: CGPoint(x: 300, y: 800), usable: usable)
        let drawn = target(CGPoint(x: 900, y: 300), anchor: anchor)
        #expect(drawn.kind == .draw)
        #expect(drawn.frame == CGRect(x: 300, y: 300, width: 600, height: 500))
        let tiny = target(CGPoint(x: 310, y: 790), anchor: anchor)
        #expect(tiny.frame == CGRect(x: 300, y: 580, width: 320, height: 220))
        let pastEdge = target(CGPoint(x: 1600, y: 10), anchor: anchor)
        #expect(pastEdge.frame == CGRect(x: 300, y: 80, width: 1140, height: 720))
    }

    @Test("The Shift anchor stays below the usable top")
    func anchorBelowMenuBar() {
        #expect(DropPlacementGeometry.drawAnchor(pointer: CGPoint(x: 10, y: 899), usable: usable) == CGPoint(x: 10, y: 875))
    }

    // MARK: Displays

    @Test("A second display left of and below the primary, with negative origins")
    func negativeOrigin() {
        let second = CGRect(x: -1920, y: -400, width: 1920, height: 1055) // visible frame, no dock
        let free = target(CGPoint(x: -1800, y: 500), usable: second)
        #expect(free.frame == CGRect(x: -1800, y: -100, width: 900, height: 600))
        let left = target(CGPoint(x: -1915, y: 0), usable: second)
        #expect(left.frame == CGRect(x: -1920, y: -400, width: 960, height: 1055))
        let right = target(CGPoint(x: -3, y: 0), usable: second)
        #expect(right.frame == CGRect(x: -960, y: -400, width: 960, height: 1055))
        let bottom = target(CGPoint(x: -1800, y: -300), usable: second)
        #expect(bottom.frame.minY == second.minY)
        #expect(bottom.frame.height == DropPlacementGeometry.minimumSize.height)
    }

    @Test("Usable frame trims a reserving dock from its own side")
    func usableFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let bottomDock = CGRect(x: 400, y: 8, width: 640, height: 64)
        #expect(DropPlacementGeometry.usableFrame(visible: visible, docks: [bottomDock])
                == CGRect(x: 0, y: 80, width: 1440, height: 795))
        let leftDock = CGRect(x: 8, y: 200, width: 64, height: 400)
        #expect(DropPlacementGeometry.usableFrame(visible: visible, docks: [leftDock])
                == CGRect(x: 80, y: 0, width: 1360, height: 875))
        let elsewhere = CGRect(x: -1000, y: 8, width: 640, height: 64)
        #expect(DropPlacementGeometry.usableFrame(visible: visible, docks: [elsewhere]) == visible)
    }
}
