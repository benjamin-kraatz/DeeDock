import CoreGraphics
import Testing

@MainActor struct DockBehaviorGeometryTests {
    @Test("Activation anchors and offsets use logical screen points, with clamping that preserves requests")
    func activation() {
        let screen = CGRect(x: -1600, y: -300, width: 1600, height: 1000)
        let glass = CGRect(x: -1100, y: -100, width: 600, height: 84)
        let envelope = CGRect(x: -1140, y: -108, width: 680, height: 200)
        var settings = DockBehaviorSettings()
        let resting = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: envelope, settings: settings)
        #expect(resting.zone.minY == glass.minY)
        #expect(resting.zone.width == glass.width)
        settings.activationLocation = .screenEdge
        let edge = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: envelope, settings: settings)
        #expect(edge.zone.minY == screen.minY)
        #expect(edge.retention.contains(CGPoint(x: glass.midX, y: -200)))
        settings.widthMode = .custom; settings.customWidth = 8192; settings.zoneOffset = 4096
        let clamped = DockActivationGeometry(screen: screen, restingGlass: glass, envelope: envelope, settings: settings)
        #expect(clamped.zone.width == screen.width)
        #expect(clamped.zone.minX == screen.minX)
        #expect(settings.customWidth == 8192 && settings.zoneOffset == 4096)
    }

    @Test("Resting activation width survives magnification and overflow; effects stay within their display")
    func envelope() {
        let screen = CGRect(x: -1200, y: 600, width: 1200, height: 800)
        var settings = DockSettings(); settings.iconSize = 96; settings.magnification = 2
        let layout = DockGeometry.layout(count: 60, favoriteCount: 5, availableWidth: screen.width, settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
        let geometry = DockPresentationGeometry(screen: screen, restingFrame: frame, layout: layout, settings: settings.behavior)
        #expect(geometry.activation.zone.width == layout.viewportWidth)
        #expect(screen.contains(geometry.windowFrame))
        #expect(geometry.contentOrigin.x + geometry.windowFrame.minX == frame.minX)
        #expect(geometry.contentOrigin.y + frame.maxY == geometry.windowFrame.maxY)
        let large = DockGeometry.layout(count: 6, favoriteCount: 3, availableWidth: screen.width, settings: settings)
        let largeFrame = DockGeometry.panelFrame(referenceFrame: screen, layout: large, settings: settings)
        let magnified = DockPresentationGeometry(screen: screen, restingFrame: largeFrame, layout: large, settings: settings.behavior)
        settings.magnification = 1
        let small = DockGeometry.layout(count: 6, favoriteCount: 3, availableWidth: screen.width, settings: settings)
        let smallFrame = DockGeometry.panelFrame(referenceFrame: screen, layout: small, settings: settings)
        let resting = DockPresentationGeometry(screen: screen, restingFrame: smallFrame, layout: small, settings: settings.behavior)
        #expect(large.panelHeight != small.panelHeight)
        #expect(magnified.activation.zone == resting.activation.zone)
    }

    @Test("Every style has safe endpoints, reversible transforms, and a reduced-motion fade", arguments: DockAnimationStyle.allCases)
    func effects(_ style: DockAnimationStyle) {
        let size = CGSize(width: 400, height: 200)
        let rect = CGRect(x: 100, y: 80, width: 80, height: 80)
        let shown = DockAnimationGeometry.sample(style: style, progress: 0, size: size, reduceMotion: false)
        let hidden = DockAnimationGeometry.sample(style: style, progress: 1, size: size, reduceMotion: false)
        #expect(shown.paintedRect(rect) == rect)
        #expect(hidden.opacity == 0)
        #expect(hidden.paintedRect(rect).isNull)
        let middle = DockAnimationGeometry.sample(style: style, progress: 0.5, size: size, reduceMotion: false)
        let point = CGPoint(x: 150, y: 130)
        let restored = middle.inverse(middle.transform(point))
        #expect(abs(restored.x - point.x) < 0.00001 && abs(restored.y - point.y) < 0.00001)
        let reduced = DockAnimationGeometry.sample(style: style, progress: 0.5, size: size, reduceMotion: true)
        #expect(reduced.scale == 1 && reduced.offset == .zero && reduced.opacity == 0.5)
        #expect(reduced.paintedRect(rect) == rect)
    }

    @Test("Wipes remove clipped click regions and bounce follows its two-stage path")
    func masksAndBounce() {
        let size = CGSize(width: 400, height: 200)
        let vertical = DockAnimationGeometry.sample(style: .verticalWipe, progress: 0.5, size: size, reduceMotion: false)
        #expect(vertical.paintedRect(CGRect(x: 40, y: 0, width: 30, height: 30)).isNull)
        let horizontal = DockAnimationGeometry.sample(style: .horizontalWipe, progress: 0.5, size: size, reduceMotion: false)
        #expect(horizontal.paintedRect(CGRect(x: 0, y: 40, width: 30, height: 30)).isNull)
        let peak = DockAnimationGeometry.sample(style: .bounceFade, progress: 0.2, size: size, reduceMotion: false)
        #expect(peak.scale == 1.04 && peak.offset.height == -6 && peak.opacity == 1)
    }
}
