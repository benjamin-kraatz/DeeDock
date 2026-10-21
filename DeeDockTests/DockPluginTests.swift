import AppKit
import Foundation
import Testing
@testable import DeeDock

/// DEE-140: pins, panel sizing, the plugin contract's tolerance, and the plugin dock section.
@MainActor
struct DockPluginTests {
    // MARK: Pins

    @Test("A newly approved plugin is pinned once, at the end of the plugin section")
    func adoptPinsNewPluginsAtTheEnd() {
        var pins = DockPluginPins()
        #expect(pins.adopt(["a", "b"]) == ["a", "b"])
        #expect(pins.adopt(["a", "b", "c"]) == ["c"])
        #expect(pins.pinned == ["a", "b", "c"])
    }

    @Test("An unpinned plugin stays unpinned when it is turned off and on again")
    func unpinnedPluginStaysUnpinned() {
        var pins = DockPluginPins()
        pins.adopt(["a", "b"])
        pins.unpin("a")
        pins.adopt(["b"])
        pins.adopt(["a", "b"])
        #expect(pins.pinned == ["b"])
        #expect(!pins.isPinned("a"))
    }

    @Test("A pinned plugin that goes away keeps its place for when it returns")
    func absentPluginKeepsItsPin() {
        var pins = DockPluginPins()
        pins.adopt(["a", "b", "c"])
        pins.adopt(["a", "c"])
        #expect(pins.pinned == ["a", "b", "c"])
        pins.pin("b")
        #expect(pins.pinned == ["a", "b", "c"])
    }

    @Test("Pins survive a save and load")
    func pinsPersist() throws {
        let suite = "DockPluginTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DockPluginPinStore(defaults: defaults)
        store.update { $0.adopt(["a", "b"]); $0.unpin("a") }
        let reloaded = DockPluginPinStore(defaults: defaults)
        var value = reloaded.value
        #expect(value.pinned == ["b"])
        #expect(value.adopt(["a"]) == [])
    }

    // MARK: Panel size

    @Test("The panel adds the header and the pointer to the plugin's content")
    func panelAddsHeaderAndPointer() {
        #expect(DockPluginPanelGeometry.panelSize(content: CGSize(width: 360, height: 280), edge: .bottom)
                == CGSize(width: 360, height: 330))
        #expect(DockPluginPanelGeometry.panelSize(content: CGSize(width: 360, height: 280), edge: .left)
                == CGSize(width: 370, height: 320))
    }

    @Test("The panel stays between 280 × 220 and 560 × 420")
    func panelClamps() {
        #expect(DockPluginPanelGeometry.panelSize(content: CGSize(width: 100, height: 40), edge: .bottom)
                == CGSize(width: 280, height: 220))
        #expect(DockPluginPanelGeometry.panelSize(content: CGSize(width: 2_000, height: 2_000), edge: .top)
                == CGSize(width: 560, height: 420))
    }

    @Test("No or unusable size falls back to the popover default",
          arguments: [nil, CGSize(width: 0, height: 200), CGSize(width: -5, height: 200), CGSize(width: CGFloat.infinity, height: 100)])
    func panelFallsBack(content: CGSize?) {
        #expect(DockPluginPanelGeometry.panelSize(content: content, edge: .bottom) == DockPopoverGeometry.idealSize)
    }

    // MARK: Contract

    @Test("A tile state with only a title decodes with every default")
    func sparseTileStateDecodes() throws {
        let state = try #require(DOKKPluginTileState.decode(Data(#"{"title":"Hi"}"#.utf8)))
        #expect(state.title == "Hi")
        #expect(state.contractVersion == 1)
        #expect(state.badge == nil && state.panelSize == nil && state.menuItems.isEmpty)
        #expect(state.primaryAction == .openPanel)
    }

    @Test("Fields from a newer plugin are skipped, not fatal")
    func newerTileStateDecodes() throws {
        let json = #"{"contractVersion":7,"title":"T","badge":{"kind":"sparkle"},"primaryAction":"teleport","future":1,"panelSize":{"width":300,"height":200}}"#
        let state = try #require(DOKKPluginTileState.decode(Data(json.utf8)))
        #expect(state.contractVersion == 7)
        #expect(state.badge == nil)
        #expect(state.primaryAction == .openPanel)
        #expect(state.panelSize == DOKKPluginSize(width: 300, height: 200))
    }

    @Test("Tile states, badges, and events survive the round trip")
    func contractRoundTrips() throws {
        let state = DOKKPluginTileState(title: "T", badge: .text("!"), accessibilityValue: "v",
                                        panelSize: DOKKPluginSize(width: 1, height: 2), primaryAction: .openApp,
                                        menuItems: [DOKKPluginMenuItem(id: "a", title: "A", systemImage: "star")])
        #expect(DOKKPluginTileState.decode(state.encoded()) == state)
        for badge in [DOKKPluginBadge.count(3), .text("new"), .dot] {
            #expect(DOKKPluginTileState.decode(DOKKPluginTileState(badge: badge).encoded())?.badge == badge)
        }
        for event in [DOKKPluginHostEvent.panelOpened, .panelClosed, .menuItemChosen("x"), .willDisconnect] {
            #expect(DOKKPluginHostEvent.decode(event.encoded()) == event)
        }
        #expect(DOKKPluginRequest.decode(DOKKPluginRequest.openApp.encoded()) == .openApp)
    }

    @Test("Unknown events and requests are dropped")
    func unknownMessagesDecodeToNil() {
        #expect(DOKKPluginHostEvent.decode(Data(#"{"kind":"later"}"#.utf8)) == nil)
        #expect(DOKKPluginRequest.decode(Data(#"{"kind":"openPanel"}"#.utf8)) == nil)
        #expect(DOKKPluginTileState.decode(Data("not json".utf8)) == nil)
    }

    // MARK: Tile

    private func plugin(badge: DOKKPluginBadge?, status: DockPluginStatus = .running) -> DockPlugin {
        DockPlugin(id: "p", extensionName: "Plugin",
                   app: DockPluginApp(name: "App", url: nil, icon: NSImage(size: CGSize(width: 16, height: 16))),
                   tileState: DOKKPluginTileState(badge: badge), status: status)
    }

    @Test("A stopped plugin hides its stale badge")
    func stoppedHidesBadge() {
        #expect(plugin(badge: .count(3)).badge?.label == "3")
        #expect(plugin(badge: .count(3), status: .stopped).badge == nil)
    }

    @Test("Badges follow the dock's rules: no zero, 99+, short text")
    func badgeLabels() {
        #expect(plugin(badge: .count(0)).badge == nil)
        #expect(plugin(badge: .count(120)).badge?.label == "99+")
        #expect(plugin(badge: .text("  longer  ")).badge?.label == "long")
        #expect(plugin(badge: .dot).badge?.style == .dot)
    }

    @Test("A session's first state is reported once, from starting or stopped")
    func firstStateOfSession() {
        let starting = plugin(badge: nil, status: .starting)
        #expect(starting.receive(DOKKPluginTileState(badge: .count(1))))
        #expect(starting.status == .running && starting.tileState?.badge == .count(1))
        #expect(!starting.receive(DOKKPluginTileState(badge: .count(2))))
        #expect(plugin(badge: nil, status: .stopped).receive(DOKKPluginTileState()))
    }

    @Test("Only a tile state ends the reply deadline, not a request")
    func replyDeadlineNeedsState() {
        #expect(DockPluginConnection.endsReplyDeadline(.state(DOKKPluginTileState())))
        #expect(!DockPluginConnection.endsReplyDeadline(.request(.closePanel)))
        #expect(!DockPluginConnection.endsReplyDeadline(.request(.openApp)))
    }

    @Test("A blank title falls back to the extension's name")
    func blankTitleFallsBack() {
        let plugin = plugin(badge: nil)
        plugin.tileState = DOKKPluginTileState(title: "   ")
        #expect(plugin.title == "Plugin")
    }

    // MARK: Dock section

    private func app(_ id: String, pinned: Bool) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: NSImage(size: CGSize(width: 48, height: 48)),
                      isFavorite: pinned, isRunning: !pinned, isAvailable: true))
    }

    private func pluginSlot(_ id: String) -> DockRenderSlot {
        .plugin(PluginDockItem(pluginID: id, title: id, icon: NSImage(size: CGSize(width: 48, height: 48)), isStopped: false))
    }

    private var slots: [DockRenderSlot] {
        [app("a", pinned: true), app("r", pinned: false), pluginSlot("p1"), pluginSlot("p2"),
         .folder(DownloadsDockItem.item(displayID: "display.test"))]
    }

    @Test("Plugins get their own section, set off by a divider on each side")
    func pluginSectionHasDividers() {
        let sections = DockLauncherPlacement.sectionCounts(slots)
        #expect(sections.favorites == 1 && sections.plugins == 2 && sections.utilities == 1)
        let layout = DockGeometry.layout(count: slots.count, favoriteCount: sections.favorites,
                                         pluginCount: sections.plugins, utilityCount: sections.utilities,
                                         availableLength: 2_000)
        #expect(layout.separatorIndices == [1, 2, 4])
    }

    @Test("Without plugins, the dividers stay where they were")
    func noPluginsKeepsDividers() {
        let layout = DockGeometry.layout(count: 3, favoriteCount: 1, utilityCount: 1, availableLength: 2_000)
        #expect(layout.separatorIndices == [1, 2])
    }

    @Test("With Islands on, plugins form their own island")
    func pluginsFormAnIsland() {
        let spans = DockIslandAssignment.spans(slots: slots, plan: .automatic, pinOrder: ["a"])
        #expect(spans.map(\.island.kind) == [.pinned, .running, .plugins, .utilities])
        #expect(spans[2].range == 2..<4)
        #expect(DockIslandPalette.color(for: .plugins) != DockIslandPalette.color(for: .running))
    }
}
