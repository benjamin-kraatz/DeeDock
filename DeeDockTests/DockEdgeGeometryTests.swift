import CoreGraphics
import Testing

@MainActor struct DockEdgeGeometryTests {
    private let screen = CGRect(x: -1800, y: -400, width: 1600, height: 1000)

    private func layout(_ settings: DockSettings, count: Int = 6) -> DockGeometry.Layout {
        DockGeometry.layout(count: count, favoriteCount: 3, availableLength: settings.edge.length(of: screen.size),
                            availableDepth: settings.edge.depth(of: screen.size), settings: settings)
    }

    @Test("Edge distance measures to resting glass and positive offsets follow item order", arguments: DockEdge.allCases)
    func placement(edge: DockEdge) {
        var settings = DockSettings(edge: edge, edgeDistance: 30)
        let layout = layout(settings)
        let frame = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
        let glass = DockGeometry.restingGlass(frame: frame, layout: layout)
        switch edge {
        case .bottom: #expect(glass.minY == screen.minY + 30)
        case .left: #expect(glass.minX == screen.minX + 30)
        case .right: #expect(glass.maxX == screen.maxX - 30)
        }
        settings.alongEdgeOffset = 50
        let moved = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
        #expect(edge.isVertical ? moved.minY == frame.minY - 50 : moved.minX == frame.minX + 50)
        var positions: [CGFloat] = []
        for alignment in DockSettings.Alignment.allCases {
            settings.alignment = alignment; settings.alongEdgeOffset = 0
            let aligned = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
            positions.append(edge.isVertical ? -aligned.maxY : aligned.minX)
        }
        #expect(positions[0] < positions[1] && positions[1] < positions[2])
        for offset in [-1000.0, 1000.0] {
            settings.alongEdgeOffset = offset; settings.edgeDistance = 300
            let clamped = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
            #expect(screen.contains(clamped))
            #expect(settings.alongEdgeOffset == offset && settings.edgeDistance == 300)
        }
    }

    @Test("Reference frames and zero edge distance apply to every physical edge", arguments: DockEdge.allCases)
    func references(edge: DockEdge) {
        let visible = screen.insetBy(dx: 70, dy: 40)
        for mode in DockSettings.PositionReference.allCases {
            let settings = DockSettings(edge: edge, edgeDistance: 0, positionReference: mode)
            let reference = DockGeometry.referenceFrame(screenFrame: screen, visibleFrame: visible, settings: settings)
            let layout = DockGeometry.layout(count: 4, favoriteCount: 2, availableLength: edge.length(of: reference.size),
                                             availableDepth: edge.depth(of: reference.size), settings: settings)
            let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
            let glass = DockGeometry.restingGlass(frame: frame, layout: layout)
            switch edge {
            case .bottom: #expect(glass.minY == reference.minY)
            case .left: #expect(glass.minX == reference.minX)
            case .right: #expect(glass.maxX == reference.maxX)
            }
        }
    }

    @Test("Magnification grows inward with a fixed outer baseline and fixed glass thickness", arguments: DockEdge.allCases)
    func magnification(edge: DockEdge) {
        let layout = layout(DockSettings(iconSize: 96, magnification: 2, itemSpacing: 10, edge: edge))
        let center = layout.restingCenters[2]
        let resting = layout.buttonFrame(centerAlong: center, size: layout.iconSize)
        let raised = layout.buttonFrame(centerAlong: center, size: layout.iconSize * 2)
        switch edge {
        case .bottom: #expect(raised.maxY == resting.maxY && raised.minY < resting.minY)
        case .left: #expect(raised.minX == resting.minX && raised.maxX > resting.maxX)
        case .right: #expect(raised.maxX == resting.maxX && raised.minX < resting.minX)
        }
        let normal = layout.surfaceFrame(sizes: layout.sizes(pointerAlong: nil, reduceMotion: false))
        let magnified = layout.surfaceFrame(sizes: layout.sizes(pointerAlong: center, reduceMotion: false))
        #expect(edge.depth(of: normal.size) == edge.depth(of: magnified.size))
        #expect(CGRect(origin: .zero, size: layout.canvasSize).contains(raised))
        #expect(layout.sizes(pointerAlong: center, reduceMotion: true).allSatisfy { $0 == layout.iconSize })
        let overflow = self.layout(DockSettings(edge: edge), count: 80)
        #expect(overflow.iconSize == 32)
        #expect(overflow.canvasLength > overflow.viewportLength)
    }

    @Test("Coordinate transforms preserve item order and invert on either side", arguments: DockEdge.allCases)
    func coordinates(edge: DockEdge) {
        let points = [CGPoint.zero, CGPoint(x: 120, y: 44), CGPoint(x: -28, y: 300)]
        for point in points {
            #expect(edge.canonical(edge.point(point, depth: 350), depth: 350) == point)
        }
        let local = CGRect(x: 5, y: 20, width: 30, height: 40)
        let global = DockEdge.screenRect(local, in: screen)
        #expect(global == CGRect(x: -1795, y: 540, width: 30, height: 40))
        let layout = layout(DockSettings(edge: edge))
        let centers = layout.restingCenters.map { edge.along(layout.iconFrame(centerAlong: $0, size: layout.iconSize).origin) }
        #expect(zip(centers, centers.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Activation follows the physical edge, length, depth, offset, and connecting region", arguments: DockEdge.allCases)
    func activation(edge: DockEdge) {
        var settings = DockSettings(edge: edge, edgeDistance: 120)
        settings.behavior.lengthMode = .custom; settings.behavior.customLength = 300
        settings.behavior.zoneDepth = 12
        let layout = layout(settings)
        let frame = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
        let glass = DockGeometry.restingGlass(frame: frame, layout: layout)
        for anchor in [DockBehaviorSettings.ActivationLocation.screenEdge, .dockPosition] {
            settings.behavior.activationLocation = anchor
            let a = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: frame, settings: settings.behavior, edge: edge)
            #expect(edge.length(of: a.zone.size) == 300 && edge.depth(of: a.zone.size) == 12)
            let boundary = anchor == .screenEdge ? screen : glass
            switch edge {
            case .bottom: #expect(a.zone.minY == boundary.minY)
            case .left: #expect(a.zone.minX == boundary.minX)
            case .right: #expect(a.zone.maxX == boundary.maxX)
            }
            #expect(a.retention.contains(a.zone) && a.retention.contains(glass))
            settings.behavior.zoneOffset = 45
            let b = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: frame, settings: settings.behavior, edge: edge)
            #expect(edge.isVertical ? b.zone.minY == a.zone.minY - 45 : b.zone.minX == a.zone.minX + 45)
            settings.behavior.zoneOffset = 0
        }
        settings.behavior.customLength = 8192; settings.behavior.zoneOffset = -4096
        let clamped = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: frame, settings: settings.behavior, edge: edge)
        #expect(screen.contains(clamped.zone))
        #expect(edge.length(of: clamped.zone.size) == edge.length(of: screen.size))
    }
}
