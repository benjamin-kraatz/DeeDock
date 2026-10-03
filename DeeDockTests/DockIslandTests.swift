import AppKit
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct DockIslandTests {
    private func icon() -> NSImage { NSImage(size: NSSize(width: 32, height: 32)) }

    private func app(_ id: String, pinned: Bool) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: icon(), isFavorite: pinned,
                      isRunning: true, isAvailable: true))
    }

    /// Launcher, one pin, one running app, Shelf, Trash. Each role is its own island.
    private func sample() -> [DockRenderSlot] {
        [.launcher, app("Safari", pinned: true), app("Terminal", pinned: false),
         .shelf(ShelfDockItem(count: 1, icon: icon())),
         .trash(TrashDockItem(state: .empty, icon: icon()))]
    }

    private func makeStore(_ slots: [DockRenderSlot]) throws -> (DockIslandStore, UserDefaults, String) {
        let name = "DockIslandTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let store = DockIslandStore(defaults: defaults)
        store.remember(displayID: "display.main", slots: slots)
        return (store, defaults, "display.main")
    }

    @Test("Automatic islands split on role and leave the dock order alone")
    func automaticSections() {
        let slots = sample()
        let breaks = DockIslandArrangement.breaks(in: slots, document: .automatic)
        #expect(breaks.map(\.start) == [0, 1, 2, 3, 4])
        #expect(breaks.map(\.title) == [.launcher, .role(.pinned), .role(.running), .role(.extras), .role(.trash)])
        #expect(DockIslandArrangement.arrangedSlots(slots, document: .automatic).map(\.id) == slots.map(\.id))

        let volume = VolumeDockItem(
            info: VolumeInfo(volumeID: "disk", url: URL(fileURLWithPath: "/Volumes/Disk"), name: "Disk",
                             kind: .removable, totalCapacity: nil, availableCapacity: nil),
            icon: icon(), isEjecting: false)
        let withDrive = [app("Safari", pinned: true), app("Terminal", pinned: false),
                         .shelf(ShelfDockItem(count: 0, icon: icon())), .volume(volume),
                         .trash(TrashDockItem(state: .empty, icon: icon()))]
        let driveBreaks = DockIslandArrangement.breaks(in: withDrive, document: .automatic)
        #expect(driveBreaks.map(\.title) == [.role(.pinned), .role(.running), .role(.extras), .role(.drives), .role(.trash)])

        // A drag gap stays inside the island it opens, including one at the start of a section.
        let gapped = [app("A", pinned: true), .gap("incoming"), app("B", pinned: true), app("Terminal", pinned: false)]
        #expect(DockIslandArrangement.breaks(in: gapped, document: .automatic).map(\.start) == [0, 3])
        let opened = [.launcher, .gap("incoming"), app("Safari", pinned: true)]
        let openedBreaks = DockIslandArrangement.breaks(in: opened, document: .automatic)
        #expect(openedBreaks.map(\.start) == [0, 1])
        #expect(openedBreaks.map(\.title) == [.launcher, .role(.pinned)])
    }

    @Test("A section button stays with its apps and is not an item someone moves")
    func groupControlsStayWithTheirRole() {
        let slots: [DockRenderSlot] = [
            .group(DockGroupControl(group: .pinned, count: 1, expanded: true)),
            app("Safari", pinned: true),
            app("Terminal", pinned: false)
        ]
        #expect(DockIslandArrangement.breaks(in: slots, document: .automatic).map(\.start) == [0, 2])
        let editor = DockIslandArrangement.editorIslands(
            snapshots: slots.compactMap(DockIslandArrangement.snapshot(of:)), document: .automatic)
        #expect(editor.map { $0.members.map(\.id) } == [["app:Safari"], ["app:Terminal"]])
    }

    @Test("Edits reorder whole islands, keep new apps on the accepting island, and survive relaunch")
    func editingPersists() throws {
        let (store, defaults, display) = try makeStore(sample())
        var edits = 0
        store.didChange = { edits += 1 }
        store.remember(displayID: display, slots: sample() + [app("Mail", pinned: false)])
        #expect(edits == 0)

        store.rename(displayID: display, islandID: "auto-1", to: "  Work  ")
        #expect(edits == 1)
        #expect(store.isCustomized(display))
        #expect(store.document(for: display).islands[1].name == "Work")
        #expect(store.resolvedTitle(store.editorIslands(for: display)[1].title) == "Work")

        store.rename(displayID: display, islandID: "auto-1", to: String(repeating: "a", count: 50))
        #expect(store.document(for: display).islands[1].name.count == 40)

        store.moveIsland(displayID: display, id: "auto-2", by: -1)
        let moved = store.arrangedSlots(sample(), displayID: display).map(\.id)
        #expect(moved == ["launcher", "app:Terminal", "app:Safari", "shelf", "system-trash"])

        store.moveMember(displayID: display, memberID: "app:Terminal", to: "auto-1")
        let joined = sample() + [app("Mail", pinned: false)]
        store.remember(displayID: display, slots: joined)
        // Renames, the island move, and the tile move. Refreshing the tile list does not count.
        #expect(edits == 4)
        let rows = store.editorIslands(for: display)
        #expect(rows.first { $0.id == "auto-1" }?.members.map(\.id) == ["app:Safari", "app:Terminal"])
        #expect(rows.first { $0.id == "auto-2" }?.members.map(\.id) == ["app:Mail"])
        // The running island was moved ahead of the pins, so Mail (still running) leads the pins.
        #expect(store.arrangedSlots(joined, displayID: display).map(\.id)
                == ["launcher", "app:Mail", "app:Safari", "app:Terminal", "shelf", "system-trash"])

        let reloaded = DockIslandStore(defaults: defaults)
        #expect(reloaded.document(for: display).islands.first { $0.id == "auto-1" }?.name == String(repeating: "a", count: 40))
        #expect(reloaded.isCustomized(display))
    }

    @Test("Deleting an island keeps its tiles, and a role with no home becomes its own band")
    func deleteMerges() throws {
        let (store, _, display) = try makeStore(sample())
        store.deleteIsland(displayID: display, id: "auto-2")
        let withMail = sample() + [app("Mail", pinned: false)]
        store.remember(displayID: display, slots: withMail)
        let rows = store.editorIslands(for: display)
        #expect(rows.filter(\.canEdit).count == 4)
        #expect(rows.first { $0.id == "auto-3" }?.members.map(\.id).contains("app:Terminal") == true)
        let leftover = try #require(rows.last)
        #expect(leftover.canEdit == false)
        #expect(leftover.members.map(\.id) == ["app:Mail"])
        #expect(store.arrangedSlots(withMail, displayID: display).map(\.id)
                == ["launcher", "app:Safari", "app:Terminal", "shelf", "system-trash", "app:Mail"])

        store.deleteIsland(displayID: display, id: leftover.id)
        #expect(store.document(for: display).islands.count == 4)

        while store.document(for: display).islands.count > 1 {
            let first = store.document(for: display).islands[0].id
            store.deleteIsland(displayID: display, id: first)
        }
        let only = store.document(for: display).islands[0].id
        store.deleteIsland(displayID: display, id: only)
        #expect(store.document(for: display).islands.map(\.id) == [only])
    }

    @Test("Reset forgets the edit, and an added island is empty until someone moves a tile onto it")
    func resetAndAdd() throws {
        let (store, defaults, display) = try makeStore(sample())
        var edits = 0
        store.didChange = { edits += 1 }
        store.addIsland(displayID: display)
        #expect(edits == 1)
        let added = try #require(store.editorIslands(for: display).last)
        #expect(added.members.isEmpty)
        #expect(added.accepts == nil)
        #expect(store.resolvedTitle(added.title) == String(localized: .islandsNewName))

        while store.document(for: display).islands.count < DockIslandDocument.maximumIslands {
            store.addIsland(displayID: display)
        }
        let full = store.document(for: display).islands.count
        store.addIsland(displayID: display)
        #expect(store.document(for: display).islands.count == full)
        #expect(full == DockIslandDocument.maximumIslands)

        store.reset(displayID: display)
        #expect(store.isCustomized(display) == false)
        #expect(store.editorIslands(for: display).map(\.id) == ["auto-0", "auto-1", "auto-2", "auto-3", "auto-4"])
        let reloaded = DockIslandStore(defaults: defaults)
        #expect(reloaded.isCustomized(display) == false)
    }

    @Test("Island frames are separate capsules, and the old divider math remains when no islands are passed")
    func geometry() {
        let layout = DockGeometry.layout(count: 4, favoriteCount: 2, availableLength: 1600,
                                         islandStarts: [0, 2], islandTitles: ["Pinned", "Running"])
        let sizes = Array(repeating: layout.iconSize, count: 4)
        let frames = layout.islandFrames(sizes: sizes)
        #expect(frames.count == 2)
        #expect(layout.islandTitles == ["Pinned", "Running"])
        #expect(layout.separatorIndices == [2])
        #expect(frames[0].minY == frames[1].minY)
        #expect(frames[0].height == frames[1].height)
        #expect(abs(frames[1].minX - frames[0].maxX - DockGeometry.islandGap) < 0.01)
        #expect(frames[0].maxX < frames[1].minX)

        var side = DockSettings.defaults
        side.edge = .left
        let vertical = DockGeometry.layout(count: 4, favoriteCount: 2, availableLength: 1600,
                                           settings: side, islandStarts: [2])
        let verticalFrames = vertical.islandFrames(sizes: sizes)
        #expect(verticalFrames.count == 2)
        #expect(abs(verticalFrames[1].minY - verticalFrames[0].maxY - DockGeometry.islandGap) < 0.01)

        let single = DockGeometry.layout(count: 3, favoriteCount: 3, availableLength: 1600)
        let singleSizes = Array(repeating: single.iconSize, count: 3)
        #expect(single.islandFrames(sizes: singleSizes) == [single.surfaceFrame(sizes: singleSizes)])
        #expect(single.separatorIndices.isEmpty)

        let counted = DockGeometry.layout(count: 4, favoriteCount: 1, utilityCount: 2, availableLength: 1600)
        #expect(counted.separatorIndices == [1, 2])
    }

    @Test("A pin gap opens beside the pin even when a running app sits in front of the pins")
    func pinGapFollowsPins() {
        let running = app("Terminal", pinned: false)
        let first = app("Safari", pinned: true)
        let second = app("Mail", pinned: true)
        let incoming = DockPin.application(DisplayFixtures.app("new"))
        let before = DockRenderSlot.slots(entries: [running, first, second],
                                          proposal: DockDragProposal(pins: [incoming], index: 0))
        #expect(before.map(\.id) == ["app:Terminal", "gap:new", "app:Safari", "app:Mail"])
        let between = DockRenderSlot.slots(entries: [running, first, second],
                                           proposal: DockDragProposal(pins: [incoming], index: 1))
        #expect(between.map(\.id) == ["app:Terminal", "app:Safari", "gap:new", "app:Mail"])
    }
}
