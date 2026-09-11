import CoreGraphics
import Testing
@testable import DeeDock

struct DockMagnetismTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let icon = CGSize(width: 48, height: 48)

    @Test("Dragging near a screen edge snaps that edge and emits an edge guide")
    func snapsToScreenEdges() {
        let frame = CGRect(origin: CGPoint(x: 8, y: 200), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [screen], peers: [])
        #expect(snap.frame.minX == 0)
        #expect(snap.frame.minY == 200)
        #expect(snap.isMagnetized)
        #expect(snap.guides.contains { $0.axis == .vertical && $0.kind == .edge && $0.position == 0 })

        let top = DockMagnetism.snap(
            frame: CGRect(origin: CGPoint(x: 400, y: screen.maxY - icon.height - 6), size: icon),
            screens: [screen], peers: []
        )
        #expect(top.frame.maxY == screen.maxY)
        #expect(top.guides.contains { $0.axis == .horizontal && $0.kind == .edge && $0.position == screen.maxY })
    }

    @Test("A gap larger than the threshold is a free drag")
    func ignoresDistantEdges() {
        let frame = CGRect(origin: CGPoint(x: DockMagnetism.threshold + 1, y: 120), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [screen], peers: [])
        #expect(snap == .free(frame))
    }

    @Test("Peer pins attract by edge and by center")
    func snapsToPeerEdgesAndCenters() {
        let peer = CGRect(x: 300, y: 80, width: 48, height: 48)
        let approachingCenter = CGRect(origin: CGPoint(x: peer.midX - icon.width / 2 + 7, y: 200), size: icon)
        let center = DockMagnetism.snap(frame: approachingCenter, screens: [screen], peers: [peer])
        #expect(center.frame.midX == peer.midX)
        #expect(center.guides.contains { $0.axis == .vertical && $0.kind == .peer && $0.position == peer.midX })

        let approachingEdge = CGRect(origin: CGPoint(x: peer.maxX - 5, y: 40), size: icon)
        let edge = DockMagnetism.snap(frame: approachingEdge, screens: [screen], peers: [peer])
        #expect(edge.frame.minX == peer.maxX)
        #expect(edge.guides.contains { $0.axis == .vertical && $0.kind == .peer && $0.position == peer.maxX })
    }

    @Test("The closer candidate wins when two alignments compete")
    func closestCandidateWins() {
        let peer = CGRect(x: 10, y: 0, width: 48, height: 48)
        // 4 pt from the screen's left edge, 6 pt from the peer's left edge.
        let frame = CGRect(origin: CGPoint(x: 4, y: 200), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [screen], peers: [peer])
        #expect(snap.frame.minX == 0)
        #expect(snap.guides.contains { $0.kind == .edge && $0.position == 0 })
        #expect(!snap.guides.contains { $0.kind == .peer && $0.position == peer.minX })
    }

    @Test("Horizontal and vertical snaps are independent")
    func snapsAxesIndependently() {
        let peer = CGRect(x: 200, y: 40, width: 48, height: 48)
        let frame = CGRect(origin: CGPoint(x: 6, y: peer.midY - icon.height / 2 + 9), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [screen], peers: [peer])
        #expect(snap.frame.minX == 0)
        #expect(snap.frame.midY == peer.midY)
        #expect(snap.guides.contains { $0.axis == .vertical && $0.kind == .edge })
        #expect(snap.guides.contains { $0.axis == .horizontal && $0.kind == .peer })
    }

    @Test("Disabled magnetism returns the original frame and no guides")
    func disabledIsNonSticky() {
        let frame = CGRect(origin: CGPoint(x: 4, y: 4), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [screen], peers: [frame.offsetBy(dx: 10, dy: 0)], enabled: false)
        #expect(snap == .free(frame))
    }

    @Test("Negative screen origins still snap to the physical edge")
    func negativeScreenOrigin() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = CGRect(origin: CGPoint(x: left.minX + 5, y: 300), size: icon)
        let snap = DockMagnetism.snap(frame: frame, screens: [left, screen], peers: [])
        #expect(snap.frame.minX == left.minX)
        #expect(snap.guides.contains { $0.axis == .vertical && $0.position == left.minX })
    }

    @Test("Guide conversion preserves alignment in a top-left overlay canvas")
    func convertsGuidesToTopLeftCanvas() {
        let canvas = CGRect(x: -100, y: 50, width: 400, height: 200)
        let guide = DockMagneticGuide(axis: .vertical, position: -100, start: 50, end: 250, kind: .edge)
        let local = guide.convertedToTopLeft(in: canvas)
        #expect(local.position == 0)
        #expect(local.start == 0)
        #expect(local.end == 200)
    }
}
