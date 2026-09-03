import Foundation
import Testing

@MainActor
struct DockTooltipTests {
    @Test("Hover delays cancel on target changes, Off, and lifecycle invalidation")
    func timing() throws {
        let scheduler = ManualDockScheduler()
        let controller = DockTooltipController(scheduler: scheduler)
        controller.update(.init(target: .app("a"), preset: .nameCard))
        let old = try #require(scheduler.lastID)
        scheduler.advance(to: 0.2)
        controller.update(.init(target: .app("b"), preset: .nameCard))
        scheduler.deliverStale(old)
        #expect(controller.visible == nil)
        scheduler.advance(to: 0.59)
        #expect(controller.visible == nil)
        scheduler.advance(to: 0.61)
        #expect(controller.visible == .app("b"))
        controller.update(.init(target: .app("b"), preset: .off))
        #expect(controller.visible == nil)
        controller.update(.init(target: .app("a"), preset: .nameCard))
        let sleep = try #require(scheduler.lastID)
        controller.clear(); scheduler.deliverStale(sleep)
        #expect(controller.visible == nil && scheduler.pendingCount == 0)
    }

    @Test("Keyboard labels are immediate, including section controls; Off remains off")
    func keyboard() {
        let scheduler = ManualDockScheduler()
        let controller = DockTooltipController(scheduler: scheduler)
        controller.update(.init(target: .group(.pinned), preset: .nameCard, keyboard: true))
        #expect(controller.visible == .group(.pinned))
        #expect(scheduler.pendingCount == 0)
        controller.update(.init(target: .group(.pinned), preset: .off, keyboard: true))
        #expect(controller.visible == nil)
    }

    @Test("Dock captions retain only valid transitions and clear on pointer exit")
    func captions() {
        let scheduler = ManualDockScheduler()
        let controller = DockTooltipController(scheduler: scheduler)
        controller.update(.init(target: .app("a"), preset: .dockTitle, keyboard: true))
        controller.update(.init(target: .app("b"), preset: .dockTitle))
        #expect(controller.visible == .app("a"))
        scheduler.advance(to: 0.2)
        #expect(controller.visible == .app("b"))
        controller.update(.init(target: nil, preset: .dockTitle))
        #expect(controller.visible == nil)
    }

    @Test("All placement families clamp long names in scrolled regions on every edge", arguments: DockEdge.allCases)
    func geometry(edge: DockEdge) {
        let region = CGRect(x: 180, y: 15, width: 210, height: 80)
        let icon = CGRect(x: 370, y: 75, width: 48, height: 48)
        let dock = CGRect(x: 180, y: 95, width: 210, height: 50)
        for placement in [DockTooltipPreset.Placement.inward, .before, .after, .dockCenter] {
            let frame = DockTooltipGeometry.frame(size: CGSize(width: 240, height: 44), icon: icon, dock: dock,
                                                  region: region, edge: edge, placement: placement)
            #expect(region.contains(frame))
            #expect(frame.width <= 240 && frame.height <= 44)
        }
    }

    @Test("Before and after try the opposite side before centering")
    func alternatePlacement() {
        let region = CGRect(x: 0, y: 0, width: 500, height: 70)
        let icon = CGRect(x: 15, y: 80, width: 48, height: 48)
        let frame = DockTooltipGeometry.frame(size: CGSize(width: 100, height: 30), icon: icon, dock: icon,
            region: region, edge: .bottom, placement: .before)
        #expect(frame.midX > icon.midX)
    }

    @Test("Tooltip reservation does not extend activation retention", arguments: DockEdge.allCases)
    func retention(edge: DockEdge) {
        var settings = DockSettings.defaults; settings.edge = edge
        let screen = CGRect(x: -1600, y: -200, width: 1600, height: 1000)
        let layout = DockGeometry.layout(count: 4, favoriteCount: 2, availableLength: edge.length(of: screen.size), settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: settings)
        let presentation = DockPresentationGeometry(screen: screen, restingFrame: frame, layout: layout, settings: settings.behavior)
        let label = layout.calloutRegion(size: layout.iconSize * layout.magnification, length: layout.viewportLength)
        let labelScreen = DockEdge.screenRect(label, in: frame)
        #expect(!presentation.activation.retention.contains(CGPoint(x: labelScreen.midX, y: labelScreen.midY)))
        #expect(presentation.activation.retention.contains(presentation.activation.zone))
    }
}
