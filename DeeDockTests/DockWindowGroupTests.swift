import AppKit
import Testing

@MainActor
struct DockWindowGroupTests {
    private var app: DockItem {
        DockItem(reference: DisplayFixtures.app("finder"), icon: NSImage(size: CGSize(width: 48, height: 48)),
                 isFavorite: true, isRunning: true, isAvailable: true)
    }
    private var windows: [DockWindowSnapshot] {
        [1, 2].map { DockWindowSnapshot(id: $0, processIdentifier: 1, applicationID: "finder", displayID: 7,
                                      title: "Same title", frame: CGRect(x: 0, y: 0, width: 100, height: 100)) }
    }
    private func entries(expanded: Bool) -> [DockRenderSlot] {
        DockWindowProjection.entries([.app(app)], windows: windows, enabled: true,
                                     keepExpanded: expanded, expandedApps: [])
    }

    @Test("Window identity survives duplicate titles and collapse repairs selection to the app disclosure")
    func collapseSelection() {
        let expanded = entries(expanded: true)
        let collapsed = entries(expanded: false)
        #expect(expanded.map(\.id) == ["app:finder", "window-group:finder", "window:1", "window:2"])
        #expect(DockSectionProjection.repairedSelection(.window(2), previous: expanded, current: collapsed) == .windowGroup("finder"))
        #expect(DockSectionProjection.repairedSelection(.window(2), previous: expanded, current: [.app(app)]) == .app("finder"))
        #expect(expanded.filter(\.isPinned).count == 4)
        #expect(expanded.compactMap(\.pin).count == 1)
    }

    @Test("Window projection cannot reveal apps excluded by the section or monitor policy")
    func respectsParentPolicy() {
        #expect(DockWindowProjection.entries([], windows: windows, enabled: true,
            keepExpanded: true, expandedApps: []).isEmpty)
        #expect(DockWindowProjection.entries([.app(app)], windows: windows, enabled: false,
            keepExpanded: true, expandedApps: []).map(\.id) == ["app:finder"])
        #expect(DockWindowProjection.entries([.app(app)], windows: [], enabled: true,
            keepExpanded: true, expandedApps: []).map(\.id) == ["app:finder"])
    }

    @Test("Pin insertion follows the whole window group and moving its parent removes its children from the preview")
    func pinInsertion() {
        let incoming = DisplayFixtures.app("new")
        let result = DockRenderSlot.slots(entries: entries(expanded: true),
            proposal: DockDragProposal(pins: [.application(incoming)], index: 1))
        #expect(result.map(\.id) == ["app:finder", "window-group:finder", "window:1", "window:2", "gap:new"])
        let moving = DockRenderSlot.slots(entries: entries(expanded: true),
            proposal: DockDragProposal(pins: [.application(app.reference)], index: 0))
        #expect(moving.map(\.id) == ["gap:finder"])
    }

    @Test("Window group preferences round-trip and older settings keep the feature off")
    func persistence() throws {
        var settings = DockSettings.defaults
        settings.windowGroupsEnabled = true
        settings.windowGroupsExpanded = true
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DockSettings.self, from: encoded) == settings)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "windowGroupsEnabled")
        object.removeValue(forKey: "windowGroupsExpanded")
        let legacy = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!legacy.windowGroupsEnabled && !legacy.windowGroupsExpanded)
    }

    @Test("Display assignment handles negative origins, spanning windows, ties, and off-screen windows")
    func displayAssignment() {
        let displays: [UInt32: CGRect] = [9: CGRect(x: -1000, y: 0, width: 1000, height: 800),
                                         2: CGRect(x: 0, y: 0, width: 1000, height: 800)]
        #expect(DockWindowDisplayAssignment.display(for: CGRect(x: -600, y: 100, width: 800, height: 400), among: displays) == 9)
        #expect(DockWindowDisplayAssignment.display(for: CGRect(x: -200, y: 100, width: 800, height: 400), among: displays) == 2)
        #expect(DockWindowDisplayAssignment.display(for: CGRect(x: -400, y: 100, width: 800, height: 400), among: displays) == 2)
        #expect(DockWindowDisplayAssignment.display(for: CGRect(x: 2000, y: 100, width: 100, height: 100), among: displays) == nil)
    }
}
