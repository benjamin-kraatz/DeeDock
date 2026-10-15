import Foundation
import Testing
@testable import DeeDock

/// The Files sidebar's Favorites: where a drag lands, how the list changes and persists, and how
/// added folders are found again after a rename.
@MainActor
struct HubFilesSidebarTests {
    private let home = URL(filePath: "/Users/tester")

    private func defaults() -> UserDefaults {
        let suite = "dokk.tests.hub.sidebar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func store(_ defaults: UserDefaults? = nil) -> HubFilesSidebarStore {
        HubFilesSidebarStore(defaults: defaults ?? self.defaults(), home: home,
                             resolver: HubFilesSidebarStaticResolver(folders: []), observesVolumes: false)
    }

    private func folder(_ path: String) -> URL { URL(filePath: path) }

    private func paths(_ store: HubFilesSidebarStore) -> [String] {
        store.entries.map { entry in
            switch entry {
            case .place(let place): place.rawValue
            case .folder(let folder): folder.path
            }
        }
    }

    // MARK: Drop layout

    /// Three 32 pt rows from y = 20; the middle one is Recents-like and takes no file drops.
    private let layout = HubFilesSidebarDropLayout(
        rows: [.init(index: 0, top: 20, bottom: 52, acceptsInto: true),
               .init(index: 1, top: 52, bottom: 84, acceptsInto: false),
               .init(index: 2, top: 84, bottom: 116, acceptsInto: true)],
        count: 3, top: 0, bottom: 150)

    @Test("A row's top and bottom quarters insert; its middle drops into its folder")
    func edgesInsertMiddleDropsInto() {
        let mode = HubFilesSidebarDropLayout.Mode.items(canInsert: true)
        #expect(layout.target(at: 22, slot: nil, mode: mode) == .insert(0))
        #expect(layout.target(at: 36, slot: nil, mode: mode) == .into(0))
        #expect(layout.target(at: 50, slot: nil, mode: mode) == .insert(1))
        // A row that takes no drops inserts on the nearer side instead.
        #expect(layout.target(at: 66, slot: nil, mode: mode) == .insert(1))
        #expect(layout.target(at: 70, slot: nil, mode: mode) == .insert(2))
    }

    @Test("A drag without folders never inserts")
    func filesOnlyNeverInsert() {
        let mode = HubFilesSidebarDropLayout.Mode.items(canInsert: false)
        #expect(layout.target(at: 22, slot: nil, mode: mode) == .into(0))
        #expect(layout.target(at: 66, slot: nil, mode: mode) == .none)
        #expect(layout.target(at: 130, slot: nil, mode: mode) == .none)
    }

    @Test("Below the last row inserts at the end; outside the area is nothing")
    func endZone() {
        let mode = HubFilesSidebarDropLayout.Mode.items(canInsert: true)
        #expect(layout.target(at: 140, slot: nil, mode: mode) == .insert(3))
        #expect(layout.target(at: 10, slot: nil, mode: mode) == .insert(0))
        #expect(layout.target(at: 160, slot: nil, mode: mode) == .none)
    }

    @Test("An open slot keeps its target under the pointer and pushes the rows below it down")
    func slotMapsBackToBaseLayout() {
        let mode = HubFilesSidebarDropLayout.Mode.items(canInsert: true)
        let slot = HubFilesSidebarDropLayout.Slot(index: 1, top: layout.slotTop(for: 1), height: 32)
        #expect(slot.top == 52)
        // Inside the slot: still "before row 1", even where row 1's middle used to be.
        #expect(layout.target(at: 66, slot: slot, mode: mode) == .insert(1))
        // Row 2 now draws 32 pt lower; its middle still means "into row 2".
        #expect(layout.target(at: 132, slot: slot, mode: mode) == .into(2))
        // Rows above the slot don't move.
        #expect(layout.target(at: 36, slot: slot, mode: mode) == .into(0))
    }

    @Test("Reordering inserts on whichever half of a row the pointer is over")
    func reorderHalves() {
        #expect(layout.target(at: 30, slot: nil, mode: .reorder) == .insert(0))
        #expect(layout.target(at: 45, slot: nil, mode: .reorder) == .insert(1))
        #expect(layout.target(at: 66, slot: nil, mode: .reorder) == .insert(1))
        #expect(layout.target(at: 110, slot: nil, mode: .reorder) == .insert(3))
    }

    @Test("A dragged row can reach the end: below the list counts the open slot's height")
    func reorderReachesTheEnd() {
        // The slot is open where the dragged first row was lifted from.
        let slot = HubFilesSidebarDropLayout.Slot(index: 0, top: layout.slotTop(for: 0), height: 32)
        #expect(layout.reorderIndex(at: 400, slot: slot) == 3)
        #expect(layout.reorderIndex(at: -50, slot: slot) == 0)
        // Just past the last drawn row (rows below the slot draw 32 pt lower).
        #expect(layout.reorderIndex(at: 116 + 32 + 4, slot: slot) == 3)
    }

    // MARK: Store

    @Test("A first launch shows the built-in places in their default order")
    func defaultsOnFirstLaunch() {
        #expect(store().entries == HubFilesSidebarEntry.defaults)
    }

    @Test("Adding folders inserts them in order; a folder already there moves instead of duplicating")
    func insertDedupes() {
        let store = store()
        store.insert([folder("/Users/tester/Projects/A"), folder("/Users/tester/Projects/B")], at: 6)
        #expect(paths(store).suffix(2) == ["/Users/tester/Projects/A", "/Users/tester/Projects/B"])

        let result = store.insert([folder("/Users/tester/Projects/B")], at: 0)
        #expect(result.added.isEmpty)
        #expect(paths(store).first == "/Users/tester/Projects/B")
        #expect(store.entries.count == 8)
    }

    @Test("A removed place's folder comes back as that place")
    func placeFolderBecomesPlace() {
        let store = store()
        store.remove(.place(.downloads))
        let result = store.insert([folder("/Users/tester/Downloads")], at: 0)
        #expect(result.added == [.place(.downloads)])
        #expect(store.entries.first == .place(.downloads))
    }

    @Test("Moving a row places it before the row now at the target index")
    func moveSemantics() {
        let store = store()
        store.move(.place(.recents), to: 3)
        #expect(paths(store).prefix(3) == ["desktop", "documents", "recents"])
        store.move(.place(.applications), to: 0)
        #expect(paths(store).first == "applications")
        store.move(.place(.desktop), to: store.entries.count)
        #expect(paths(store).last == "desktop")
    }

    @Test("Undo puts a removed row back where it was")
    func removeAndRestore() throws {
        let store = store()
        store.insert([folder("/Users/tester/Projects/A")], at: 2)
        let id = store.entries[2].id
        let removal = store.remove(id)
        #expect(store.index(of: id) == nil)
        store.restore(try #require(removal))
        #expect(store.index(of: id) == 2)
    }

    @Test("Removing several rows in one command undoes as one, each back in its old place")
    func batchRemovalUndo() {
        let sidebar = HubFilesSidebarModel(store: store())
        let before = paths(sidebar.store)
        sidebar.remove([.place(.desktop), .place(.home)], method: .menu, animated: false)
        #expect(paths(sidebar.store) == ["recents", "documents", "downloads", "applications"])
        #expect(sidebar.undo?.removals.count == 2)

        #expect(sidebar.undoRemoval())
        #expect(paths(sidebar.store) == before)
        #expect(!sidebar.undoRemoval())
    }

    @Test("Undo after the folder was added again moves that row back instead of duplicating it")
    func undoAfterReAddDoesNotDuplicate() throws {
        let store = store()
        store.insert([folder("/Users/tester/Projects/A")], at: 1)
        let removal = try #require(store.remove(store.entries[1].id))
        store.insert([folder("/Users/tester/Projects/A")], at: store.entries.count)

        store.restore(removal)
        #expect(paths(store).filter { $0 == "/Users/tester/Projects/A" }.count == 1)
        #expect(paths(store)[1] == "/Users/tester/Projects/A")
    }

    @Test("Undo puts a folder re-added above its old place back at that exact position")
    func undoAfterReAddAboveOriginalPosition() throws {
        let store = store()
        store.insert([folder("/Users/tester/Projects/A")], at: 2)
        let removal = try #require(store.remove(store.entries[2].id))
        store.insert([folder("/Users/tester/Projects/A")], at: 0)

        store.restore(removal)
        #expect(paths(store)[2] == "/Users/tester/Projects/A")
        #expect(paths(store).filter { $0 == "/Users/tester/Projects/A" }.count == 1)
    }

    @Test("A stored list never yields two rows for the same folder path")
    func snapshotDedupesFolderPaths() {
        let path = "/Users/tester/Projects/A"
        let snapshot = HubFilesSidebarSnapshot(entries: [
            .folder(HubFilesSidebarFolder(path: path)), .place(.desktop), .folder(HubFilesSidebarFolder(path: path))
        ])
        #expect(snapshot.entries.count == 2)
    }

    @Test("Restore Default Places brings removed places back in order and keeps added folders")
    func restoreDefaultPlaces() {
        let store = store()
        store.insert([folder("/Users/tester/Projects/A")], at: 0)
        store.remove(.place(.recents))
        store.remove(.place(.downloads))
        #expect(store.missingPlaces == [.recents, .downloads])

        let restored = store.restoreDefaultPlaces()
        #expect(restored == [.recents, .downloads])
        #expect(paths(store) == ["recents", "/Users/tester/Projects/A", "desktop", "documents", "downloads",
                                 "home", "applications"])
        #expect(store.restoreDefaultPlaces().isEmpty)
    }

    @Test("The list persists, and an unknown place from a newer build is skipped")
    func persistence() throws {
        let defaults = defaults()
        let first = store(defaults)
        first.remove(.place(.applications))
        first.insert([folder("/Users/tester/Projects/A")], at: 1)
        #expect(paths(store(defaults)) == paths(first))

        var snapshot = HubFilesSidebarSnapshot(entries: first.entries)
        snapshot.items.insert(.place("timeMachine"), at: 0)
        snapshot.save(to: defaults)
        #expect(paths(store(defaults)) == paths(first))
    }

    // MARK: Resolution

    @Test("A bookmarked folder is found again after a rename; a deleted one is missing")
    func bookmarkFollowsRename() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "dokk-sidebar-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let original = root.appending(path: "Projects")
        try fileManager.createDirectory(at: original, withIntermediateDirectories: true)

        let resolver = HubFilesSidebarBookmarkResolver()
        // Without a bookmark, the last known path finds it and a bookmark is created.
        let first = resolver.resolve(HubFilesSidebarFolder(path: FilePathCopy.path(of: original)))
        #expect(first.status == .available)
        let bookmark = try #require(first.refreshedBookmark)

        let renamed = root.appending(path: "Projects 2026")
        try fileManager.moveItem(at: original, to: renamed)
        let followed = resolver.resolve(HubFilesSidebarFolder(path: FilePathCopy.path(of: original), bookmark: bookmark))
        #expect(followed.status == .available)
        #expect(followed.url.lastPathComponent == "Projects 2026")

        try fileManager.removeItem(at: renamed)
        let gone = resolver.resolve(HubFilesSidebarFolder(path: FilePathCopy.path(of: renamed), bookmark: bookmark))
        #expect(gone.status == .missing)
    }
}
