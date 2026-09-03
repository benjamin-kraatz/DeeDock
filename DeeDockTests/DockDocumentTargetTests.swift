import AppKit
import Testing

@MainActor
struct DockDocumentTargetTests {
    @Test("Only visible available app frames receive files, on every edge", arguments: DockEdge.allCases)
    func targets(edge: DockEdge) {
        let image = NSImage(size: CGSize(width: 48, height: 48))
        let pin = DockItem(reference: DisplayFixtures.app("pin"), icon: image, isFavorite: true, isRunning: false, isAvailable: true)
        let running = DockItem(reference: DisplayFixtures.app("run"), icon: image, isFavorite: false, isRunning: true, isAvailable: true)
        let missing = DockItem(reference: DisplayFixtures.app("missing"), icon: image, isFavorite: true, isRunning: false, isAvailable: false)
        let entries: [DockRenderSlot] = [.app(pin), .app(missing), .group(.init(group: .running, count: 1, expanded: true)), .app(running)]
        let depth: CGFloat = 100
        let frames = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.id, edge.rect(CGRect(x: CGFloat(index) * 60, y: 30, width: 48, height: 48), depth: depth))
        })
        let mask = edge.rect(CGRect(x: 0, y: 0, width: 210, height: depth), depth: depth)
        func target(_ x: CGFloat, entries: [DockRenderSlot]? = nil, exposed: Bool = true) -> DockItem? {
            DockDocumentTarget.app(at: edge.point(CGPoint(x: x, y: 50), depth: depth), entries: entries ?? [.app(pin), .app(missing), .group(.init(group: .running, count: 1, expanded: true)), .app(running)], frames: frames, mask: mask, exposed: exposed)
        }
        #expect(target(20)?.id == pin.id)
        #expect(target(195)?.id == running.id)
        #expect(target(220) == nil) // App frame continues beyond the visible animation clip.
        #expect(target(55) == nil) // Spacing.
        #expect(target(80) == nil) // Unavailable pin.
        #expect(target(135) == nil) // Group button.
        #expect(target(20, entries: [.app(running)]) == nil) // A stale removed frame.
        #expect(target(20, exposed: false) == nil)
    }

    @Test("Document operations never ask the source to move or delete files")
    func operations() {
        #expect(DockDocumentTarget.operation(allowed: [.generic, .copy, .move]) == .generic)
        #expect(DockDocumentTarget.operation(allowed: [.copy, .move]) == .copy)
        #expect(DockDocumentTarget.operation(allowed: [.move, .delete, .link]).isEmpty)
    }

    @Test("Native spring callbacks activate once per visit and reset between apps or displays")
    func springVisits() {
        var spring = DockSpringTarget()
        let withoutTarget = spring.activate()
        let firstVisit = spring.update("display-a:app")
        let firstActivation = spring.activate()
        let sameVisit = spring.update("display-a:app")
        let repeatedActivation = spring.activate()
        #expect(!withoutTarget && firstVisit && firstActivation)
        #expect(!sameVisit && !repeatedActivation)
        spring.update("display-b:app")
        let secondActivation = spring.activate()
        #expect(secondActivation)
        spring.update(nil)
        let afterExit = spring.activate()
        #expect(!afterExit)
        spring.update("display-b:app")
        let reentered = spring.activate()
        #expect(reentered)
    }

    @Test("Document dwell expands either collapsed section and restores session state", arguments: [DockAppVisibility.collapsePinned, .collapseRunning])
    func sections(mode: DockAppVisibility) throws {
        let scheduler = ManualDockScheduler()
        let state = DockSectionState(scheduler: scheduler)
        state.configure(mode)
        state.dragHover(true, documents: true)
        let stale = try #require(scheduler.lastID)
        state.dragHover(false, documents: true)
        scheduler.deliverStale(stale)
        #expect(!state.isExpanded)
        state.dragHover(true, documents: true)
        scheduler.advance(to: 0.49)
        #expect(!state.isExpanded)
        scheduler.advance(to: 0.5)
        #expect(state.dragExpanded)
        state.endDrag()
        #expect(!state.isExpanded)
        state.toggle()
        state.dragHover(true, documents: true)
        state.endDrag()
        #expect(state.expanded)
        state.configure(.hideRunning)
        state.dragHover(true, documents: true)
        #expect(scheduler.pendingCount == 0)
    }
}
