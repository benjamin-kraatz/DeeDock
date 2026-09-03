import CoreGraphics
import Testing

@MainActor struct DockEdgeInteractionTests {
    @Test("All animation styles use the same invertible oriented masks for painting and input", arguments: DockEdge.allCases, DockAnimationStyle.allCases)
    func animations(edge: DockEdge, style: DockAnimationStyle) {
        let size = edge.size(length: 500, depth: 350)
        let shown = DockAnimationGeometry.sample(style: style, progress: 0, size: size, reduceMotion: false, edge: edge)
        #expect(shown.mask == CGRect(origin: .zero, size: size))
        #expect(shown.scale == 1 && shown.opacity == 1 && shown.offset == .zero)
        let hidden = DockAnimationGeometry.sample(style: style, progress: 1, size: size, reduceMotion: false, edge: edge)
        #expect(hidden.opacity == 0 && hidden.mask.isEmpty)
        for progress in [0.1, 0.4, 0.8] {
            let sample = DockAnimationGeometry.sample(style: style, progress: progress, size: size, reduceMotion: false, edge: edge)
            let point = CGPoint(x: sample.mask.midX, y: sample.mask.midY)
            let roundTrip = sample.inverse(sample.transform(point))
            #expect(abs(roundTrip.x - point.x) < 0.00001 && abs(roundTrip.y - point.y) < 0.00001)
            let rect = CGRect(origin: .zero, size: size)
            #expect(sample.paintedRect(rect).contains(sample.transform(point)))
            let reduced = DockAnimationGeometry.sample(style: style, progress: progress, size: size, reduceMotion: true, edge: edge)
            #expect(reduced.offset == .zero && reduced.scale == 1 && reduced.mask == rect)
            #expect(reduced.opacity == 1 - progress)
        }
    }

    @Test("Outward, inward, start and end animations follow physical placement", arguments: DockEdge.allCases)
    func directions(edge: DockEdge) {
        let size = edge.size(length: 400, depth: 300)
        let outward = DockAnimationGeometry.sample(style: .slideFade, progress: 0.5, size: size, reduceMotion: false, edge: edge)
        let inward = DockAnimationGeometry.sample(style: .liftFade, progress: 0.5, size: size, reduceMotion: false, edge: edge)
        switch edge {
        case .bottom: #expect(outward.offset.height > 0 && inward.offset.height < 0)
        case .top: #expect(outward.offset.height < 0 && inward.offset.height > 0)
        case .left: #expect(outward.offset.width < 0 && inward.offset.width > 0)
        case .right: #expect(outward.offset.width > 0 && inward.offset.width < 0)
        }
        let start = DockAnimationGeometry.sample(style: .leftFade, progress: 0.5, size: size, reduceMotion: false, edge: edge)
        let end = DockAnimationGeometry.sample(style: .rightFade, progress: 0.5, size: size, reduceMotion: false, edge: edge)
        #expect(edge.isVertical ? start.offset.height < 0 && end.offset.height > 0 : start.offset.width < 0 && end.offset.width > 0)
        let wipe = DockAnimationGeometry.sample(style: .verticalWipe, progress: 0.5, size: size, reduceMotion: false, edge: edge)
        switch edge {
        case .bottom: #expect(wipe.mask.maxY == size.height - DockGeometry.outerMargin)
        case .top: #expect(wipe.mask.minY == DockGeometry.outerMargin)
        case .left: #expect(wipe.mask.minX == DockGeometry.outerMargin)
        case .right: #expect(wipe.mask.maxX == size.width - DockGeometry.outerMargin)
        }
    }

    @Test("Insertion and autoscroll use the ordered axis after scrolling", arguments: DockEdge.allCases)
    func dragGeometry(edge: DockEdge) {
        let layout = DockGeometry.layout(count: 40, favoriteCount: 30, availableLength: 600, settings: DockSettings(edge: edge))
        let point = edge.point(CGPoint(x: layout.restingCenters[12] - 200 + 1, y: layout.panelDepth - 20), depth: layout.panelDepth)
        #expect(DockDragGeometry.insertion(point: point, scrollOffset: -200, layout: layout, pinCount: 30) == 13)
        let running = edge.point(CGPoint(x: layout.restingCenters[35], y: layout.panelDepth - 20), depth: layout.panelDepth)
        #expect(DockDragGeometry.insertion(point: running, scrollOffset: 0, layout: layout, pinCount: 30) == nil)
        for position in [CGFloat(0), 300, 600] {
            let physical = edge.point(CGPoint(x: position, y: 100), depth: layout.panelDepth)
            let speed = DockDragGeometry.scrollVelocity(position: edge.along(physical), length: 600)
            #expect(position == 0 ? speed < 0 : (position == 600 ? speed > 0 : speed == 0))
        }
        let frame = CGRect(origin: CGPoint(x: -1600, y: -300), size: layout.viewportSize)
        let glass = DockGeometry.restingGlass(frame: frame, layout: layout, scrollOffset: -200)
        let far = CGPoint(x: glass.maxX + 64, y: glass.midY)
        #expect(DockDragGeometry.distance(far, outside: glass) == 64)
        #expect(DockDragCompletion(released: true).shouldUnpin(isPinned: true, distance: 64, overDock: false))
        #expect(!DockDragCompletion(released: true, cancelled: true).shouldUnpin(isPinned: true, distance: 64, overDock: false))
    }

    @Test("Transparent source label space cannot prevent 64-point unpinning; another dock still protects rejection")
    func removalProtection() {
        let glass = CGRect(x: -1500, y: -200, width: 64, height: 400)
        let retention = CGRect(x: -1500, y: -200, width: 350, height: 400)
        let point = CGPoint(x: glass.maxX + 64, y: glass.midY)
        #expect(retention.contains(point))
        #expect(!DockDragGeometry.protectsRemoval(at: point, isSource: true, restingGlass: glass, retention: retention))
        #expect(DockDragGeometry.protectsRemoval(at: point, isSource: false, restingGlass: glass, retention: retention))
    }

    @Test("Only parallel arrows navigate; the same step drives accessible reordering", arguments: DockEdge.allCases)
    func keys(edge: DockEdge) {
        #expect(edge.navigationStep(keyCode: edge.isVertical ? 126 : 123) == -1)
        #expect(edge.navigationStep(keyCode: edge.isVertical ? 125 : 124) == 1)
        #expect(edge.navigationStep(keyCode: edge.isVertical ? 123 : 126) == nil)
        #expect(edge.navigationStep(keyCode: edge.isVertical ? 124 : 125) == nil)
    }

    @Test("Changing edge cancels obsolete reveal and animation callbacks without revealing a hidden dock")
    func staleVisibility() throws {
        let clock = ManualDockScheduler()
        var settings = DockSettings(edge: .bottom)
        settings.behavior.autoHide = true
        let controller = DockVisibilityController(settings: settings.behavior, scheduler: clock)
        controller.update(activation: true, retained: true, held: false)
        let oldDwell = try #require(clock.lastID)
        settings.edge = .left
        controller.configure(settings.behavior, reduceMotion: false, geometryChanged: true)
        controller.update(activation: false, retained: false, held: false)
        clock.deliverStale(oldDwell); clock.advance(to: 1)
        #expect(controller.progress == 1 && clock.pendingCount == 0)
        controller.update(activation: false, retained: false, held: true)
        let oldFrame = try #require(clock.lastID)
        settings.edge = .right
        controller.configure(settings.behavior, reduceMotion: false, geometryChanged: true)
        controller.update(activation: false, retained: false, held: true)
        clock.deliverStale(oldFrame)
        #expect(controller.progress == 0)
        controller.stop()
        clock.deliverStale(oldFrame)
        #expect(controller.phase == .hidden && clock.pendingCount == 0)
    }
}
