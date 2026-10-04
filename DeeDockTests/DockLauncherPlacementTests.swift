import AppKit
import Testing
@testable import DeeDock

@MainActor
struct DockLauncherPlacementTests {
    private func pinned(_ id: String) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: NSImage(size: CGSize(width: 48, height: 48)),
                      isFavorite: true, isRunning: false, isAvailable: true))
    }

    private func running(_ id: String) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: NSImage(size: CGSize(width: 48, height: 48)),
                      isFavorite: false, isRunning: true, isAvailable: true))
    }

    private var downloads: DockRenderSlot { .folder(DownloadsDockItem.item(displayID: "display.test")) }

    /// Pins a, b, c, one running app, and the Downloads utility.
    private var content: [DockRenderSlot] { [pinned("a"), pinned("b"), pinned("c"), running("r"), downloads] }

    private func ids(_ slots: [DockRenderSlot]) -> [String] { slots.map(\.id) }

    // MARK: Persistence

    @Test("Older settings keep their launcher end; new settings default to the far start")
    func legacySettingsMigrate() throws {
        let encoded = try JSONEncoder().encode(DockSettings.defaults)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "launcherPosition")
        let absent = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(absent.launcherPosition == .start)
        object["launcherAtStart"] = false
        let trailing = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(trailing.launcherPosition == .end)
    }

    @Test("A display override from before DEE-84 still overrides", arguments: [true, false])
    func legacyOverrideMigrates(atStart: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: ["launcherAtStart": atStart])
        let overrides = try JSONDecoder().decode(DockSettingsOverrides.self, from: data)
        #expect(overrides.launcherPosition == (atStart ? .start : .end))
        #expect(overrides.contains(.launcherPosition))
    }

    @Test("Every position survives a save and reload", arguments: [LauncherDockPosition.start, .end, .afterPin("com.apple.Safari")])
    func positionRoundTrips(position: LauncherDockPosition) throws {
        var settings = DockSettings.defaults
        settings.launcherPosition = position
        let restored = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.launcherPosition == position)
        var overrides = DockSettingsOverrides()
        overrides.set(.launcherPosition, from: settings)
        let reloaded = try JSONDecoder().decode(DockSettingsOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(reloaded.resolving(.defaults).launcherPosition == position)
    }

    // MARK: Placement

    @Test("The launcher leads, trails, or follows its anchor pin")
    func placement() {
        #expect(ids(DockLauncherPlacement.entries(content, position: .start, pinOrder: ["a", "b", "c"])).first == "launcher")
        #expect(ids(DockLauncherPlacement.entries(content, position: .end, pinOrder: ["a", "b", "c"])).last == "launcher")
        let afterB = DockLauncherPlacement.entries(content, position: .afterPin("b"), pinOrder: ["a", "b", "c"])
        #expect(ids(afterB) == ["app:a", "app:b", "launcher", "app:c", "app:r", downloads.id])
        #expect(DockLauncherPlacement.renderedPosition(in: afterB) == .afterPin("b"))
    }

    @Test("A hidden anchor falls back to the nearest earlier visible pin, then the start")
    func hiddenAnchorFallsBack() {
        let withoutB = content.filter { $0.id != "app:b" }
        let fallback = DockLauncherPlacement.entries(withoutB, position: .afterPin("b"), pinOrder: ["a", "b", "c"])
        #expect(ids(fallback).prefix(3) == ["app:a", "launcher", "app:c"])
        let unknown = DockLauncherPlacement.entries(content, position: .afterPin("gone"), pinOrder: ["a", "b", "c"])
        #expect(ids(unknown).first == "launcher")
        let firstHidden = DockLauncherPlacement.entries(content.filter { $0.id != "app:a" }, position: .afterPin("a"),
                                                        pinOrder: ["a", "b", "c"])
        #expect(ids(firstHidden).first == "launcher")
    }

    @Test("Moving or unpinning the anchor leaves the launcher where it was")
    func reanchoring() {
        let position = LauncherDockPosition.afterPin("b")
        // Unrelated edits keep the anchor.
        #expect(DockLauncherPlacement.reanchored(position, previous: ["a", "b", "c"], next: ["a", "b", "c", "d"]) == position)
        #expect(DockLauncherPlacement.reanchored(position, previous: ["a", "b", "c"], next: ["c", "a", "b"], relocated: ["c"]) == position)
        // The anchor itself leaves or moves: follow its predecessor.
        #expect(DockLauncherPlacement.reanchored(position, previous: ["a", "b", "c"], next: ["a", "c"]) == .afterPin("a"))
        #expect(DockLauncherPlacement.reanchored(position, previous: ["a", "b", "c"], next: ["a", "c", "b"], relocated: ["b"]) == .afterPin("a"))
        // The predecessor moved along with the anchor, so skip it as well.
        #expect(DockLauncherPlacement.reanchored(.afterPin("c"), previous: ["a", "b", "c"], next: ["b", "c", "a"],
                                                 relocated: ["b", "c"]) == .afterPin("a"))
        // No predecessor remains.
        #expect(DockLauncherPlacement.reanchored(.afterPin("a"), previous: ["a", "b"], next: ["b"]) == .start)
        #expect(DockLauncherPlacement.reanchored(.end, previous: ["a"], next: []) == .end)
    }

    @Test("Stops cover both ends and the space after every visible pin")
    func stops() {
        #expect(DockLauncherPlacement.stops(in: content) == [.start, .afterPin("a"), .afterPin("b"), .afterPin("c"), .end])
        #expect(DockLauncherPlacement.stops(in: [running("r")]) == [.start, .end])
    }

    // MARK: Layout

    @Test("Dividers: a leading launcher has its own, one among pins joins them, a trailing one joins utilities")
    func sectionCounts() {
        let order = ["a", "b", "c"]
        let leading = DockLauncherPlacement.sectionCounts(DockLauncherPlacement.entries(content, position: .start, pinOrder: order))
        #expect(leading.leading == 1 && leading.favorites == 3 && leading.utilities == 1)
        let among = DockLauncherPlacement.sectionCounts(DockLauncherPlacement.entries(content, position: .afterPin("b"), pinOrder: order))
        #expect(among.leading == 0 && among.favorites == 4 && among.utilities == 1)
        let afterLast = DockLauncherPlacement.sectionCounts(DockLauncherPlacement.entries(content, position: .afterPin("c"), pinOrder: order))
        #expect(afterLast.leading == 0 && afterLast.favorites == 4 && afterLast.utilities == 1)
        let trailing = DockLauncherPlacement.sectionCounts(DockLauncherPlacement.entries(content, position: .end, pinOrder: order))
        #expect(trailing.leading == 0 && trailing.favorites == 3 && trailing.utilities == 2)
    }

    // MARK: Drag previews

    @Test("A launcher drag replaces the tile with a gap at the proposed stop")
    func launcherDragPreview() {
        let entries = DockLauncherPlacement.entries(content, position: .start, pinOrder: ["a", "b", "c"])
        let afterA = DockRenderSlot.slots(entries: entries, proposal: DockDragProposal(index: 1, utilityID: DockEntryID.launcher.hitID))
        #expect(ids(afterA) == ["app:a", "gap:launcher", "app:b", "app:c", "app:r", downloads.id])
        let atEnd = DockRenderSlot.slots(entries: entries, proposal: DockDragProposal(index: 4, utilityID: DockEntryID.launcher.hitID))
        #expect(ids(atEnd).last == "gap:launcher")
        #expect(DockLauncherPlacement.sectionCounts(afterA).favorites == 4)
    }

    @Test("A pin gap lands where the dropped pin will render around a launcher among pins")
    func pinGapAroundLauncher() {
        let entries = DockLauncherPlacement.entries(content, position: .afterPin("b"), pinOrder: ["a", "b", "c"])
        let incoming = DockPin.application(DisplayFixtures.app("new"))
        // Inserting after b puts the pin after the launcher, which keeps following b.
        let afterB = DockRenderSlot.slots(entries: entries, proposal: DockDragProposal(pins: [incoming], index: 2))
        #expect(ids(afterB).prefix(5) == ["app:a", "app:b", "launcher", "gap:new", "app:c"])
        let first = DockRenderSlot.slots(entries: entries, proposal: DockDragProposal(pins: [incoming], index: 0))
        #expect(ids(first).prefix(2) == ["gap:new", "app:a"])
        let afterLast = DockLauncherPlacement.entries(content, position: .afterPin("c"), pinOrder: ["a", "b", "c"])
        let appended = DockRenderSlot.slots(entries: afterLast, proposal: DockDragProposal(pins: [incoming], index: 3))
        #expect(ids(appended).prefix(5) == ["app:a", "app:b", "app:c", "launcher", "gap:new"])
    }
}
