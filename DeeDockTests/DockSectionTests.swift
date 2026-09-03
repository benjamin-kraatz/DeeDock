import AppKit
import Testing

@MainActor
struct DockSectionTests {
    private var items: [DockItem] {
        let image = NSImage(size: CGSize(width: 48, height: 48))
        return [DockItem(reference: DisplayFixtures.app("pin"), icon: image, isFavorite: true, isRunning: true, isAvailable: true),
                DockItem(reference: DisplayFixtures.app("missing"), icon: image, isFavorite: true, isRunning: false, isAvailable: false),
                DockItem(reference: DisplayFixtures.app("running"), icon: image, isFavorite: false, isRunning: true, isAvailable: true)]
    }

    @Test("Visibility preserves membership, including running and unavailable pins", arguments: DockAppVisibility.allCases)
    func grouping(mode: DockAppVisibility) {
        let entries = DockSectionProjection.entries(items: items, visibility: mode, expanded: false)
        let expected: [String]
        switch mode {
        case .showAll: expected = ["app:pin", "app:missing", "app:running"]
        case .hideRunning: expected = ["app:pin", "app:missing"]
        case .collapseRunning: expected = ["app:pin", "app:missing", "group:running"]
        case .hidePinned: expected = ["app:running"]
        case .collapsePinned: expected = ["group:pinned", "app:running"]
        }
        #expect(entries.map(\.id) == expected)
        #expect(items[0].isFavorite && items[0].isRunning)
        if let group = mode.collapsedGroup {
            let expanded = DockSectionProjection.entries(items: items, visibility: mode, expanded: true)
            #expect(expanded.compactMap(\.item).map(\.id) == items.map(\.id))
            #expect(expanded.contains { $0.target == .group(group) })
        }
    }

    @Test("Empty collapsed groups keep an accessible zero-count control")
    func empty() throws {
        for mode in [DockAppVisibility.collapsePinned, .collapseRunning] {
            let entries = DockSectionProjection.entries(items: [], visibility: mode, expanded: false)
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            guard case .group(let control) = entry else { Issue.record("Missing group control"); return }
            #expect(control.count == 0)
            #expect(!control.expanded)
        }
        #expect(DockSectionProjection.entries(items: Array(items.prefix(2)), visibility: .hidePinned, expanded: false).isEmpty)
    }

    @Test("Collapsing repairs app selection to its group; hiding uses the nearest remaining entry")
    func selection() {
        let expanded = DockSectionProjection.entries(items: items, visibility: .collapsePinned, expanded: true)
        let collapsed = DockSectionProjection.entries(items: items, visibility: .collapsePinned, expanded: false)
        #expect(DockSectionProjection.repairedSelection(.app("missing"), previous: expanded, current: collapsed) == .group(.pinned))
        #expect(DockSectionProjection.repairedSelection(.group(.pinned), previous: collapsed, current: expanded) == .group(.pinned))
        let hidden = DockSectionProjection.entries(items: items, visibility: .hidePinned, expanded: false)
        #expect(DockSectionProjection.repairedSelection(.app("pin"), previous: expanded, current: hidden) == .app("running"))
        #expect(DockSectionProjection.repairedSelection(.app("pin"), previous: expanded, current: []) == nil)
    }

    @Test("Expansion is independent and resets only for a new policy or session")
    func sessions() {
        let a = DockSectionState(), b = DockSectionState()
        a.configure(.collapseRunning); b.configure(.collapseRunning)
        a.toggle(); a.configure(.collapseRunning)
        #expect(a.isExpanded && !b.isExpanded)
        a.configure(.collapsePinned)
        #expect(!a.isExpanded)
        a.toggle(); a.endDrag()
        #expect(a.isExpanded)
        a.toggle()
        #expect(!a.isExpanded)
    }

    @Test("Drag dwell cancels stale callbacks and restores the previous expansion")
    func dragDwell() throws {
        let scheduler = ManualDockScheduler()
        let state = DockSectionState(scheduler: scheduler)
        state.configure(.collapsePinned)
        state.dragHover(true)
        let cancelled = try #require(scheduler.lastID)
        scheduler.advance(to: 0.49)
        #expect(!state.isExpanded)
        state.dragHover(false); scheduler.deliverStale(cancelled)
        #expect(!state.isExpanded)
        state.dragHover(true); scheduler.advance(to: 0.99)
        #expect(state.dragExpanded && !state.expanded)
        state.dragHover(false)
        #expect(state.isExpanded)
        state.endDrag()
        #expect(!state.isExpanded && scheduler.pendingCount == 0)
        state.toggle(); state.dragHover(true); state.endDrag()
        #expect(state.expanded && scheduler.pendingCount == 0)
        state.toggle(); state.dragHover(true)
        let changed = try #require(scheduler.lastID)
        state.configure(.hidePinned); scheduler.deliverStale(changed)
        #expect(!state.isExpanded)
    }

    @Test("Visible pin insertion excludes controls and rejects hidden pins", arguments: DockEdge.allCases)
    func insertion(edge: DockEdge) {
        var settings = DockSettings.defaults; settings.edge = edge
        let entries = DockSectionProjection.entries(items: items, visibility: .collapsePinned, expanded: true)
        let layout = DockGeometry.layout(count: entries.count, favoriteCount: 3, availableLength: 600, settings: settings)
        func index(_ position: CGFloat, mode: DockAppVisibility = .collapsePinned) -> Int? {
            let point = edge.point(CGPoint(x: position - 20, y: layout.panelDepth - 20), depth: layout.panelDepth)
            return DockSectionInsertion.index(point: point, scrollOffset: -20, layout: layout, entries: entries, pinCount: 2, visibility: mode)
        }
        #expect(index(layout.restingCenters[0]) == 2)
        #expect(index(layout.restingCenters[1] - 1) == 0)
        #expect(index(layout.restingCenters[1] + 1) == 1)
        #expect(index(layout.restingCenters[2] + 1) == 2)
        #expect(index(layout.restingCenters[3]) == nil)
        #expect(index(layout.restingCenters[1], mode: .hidePinned) == nil)
        let proposal = DockDragProposal(pins: [.application(DisplayFixtures.app("pin"))], index: 2)
        let slots = DockRenderSlot.slots(entries: entries, proposal: proposal)
        #expect(slots.map(\.id) == ["group:pinned", "app:missing", "gap:pin", "app:running"])
        let collapsed = DockSectionProjection.entries(items: items, visibility: .collapsePinned, expanded: false)
        #expect(DockRenderSlot.slots(entries: collapsed, proposal: proposal).map(\.id) == collapsed.map(\.id))
    }

    @Test("Removed app geometry cannot be reintroduced by an exiting view")
    func hiddenHitRegions() {
        let interaction = DockInteraction()
        let rect = CGRect(x: 0, y: 0, width: 48, height: 48)
        interaction.setIconRect(rect, for: "app:pin")
        interaction.retainHitRegions(["group:pinned"])
        interaction.setIconRect(rect, for: "app:pin")
        #expect(interaction.iconRects["app:pin"] == nil)
        interaction.setIconRect(rect, for: "group:pinned")
        #expect(interaction.iconRects["group:pinned"] == rect)
    }
}
