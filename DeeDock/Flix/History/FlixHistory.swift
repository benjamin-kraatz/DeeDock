import Foundation
import Observation

/// DOKK's own Flix Files history, in memory, with its library of Favorites and Smart Filters.
///
/// Sources call ``record(_:)``; the panel and the tile read ``items``. Every change schedules a
/// debounced write through ``FlixJSONFile`` off the main actor, so recording never waits for the
/// disk. Main actor only. A history built without files (previews, tests) keeps everything in
/// memory and never touches the disk.
@MainActor @Observable
final class FlixHistory {
    private(set) var document: FlixHistoryDocument
    private(set) var library: FlixLibraryDocument
    /// Set when a saved file could not be read. It was moved aside (see ``FlixJSONFile/quarantine()``)
    /// and Flix Files started over, so a broken file never stops it from working.
    private(set) var recoveredFromUnreadableFile = false

    @ObservationIgnored private let historyFile: FlixJSONFile<FlixHistoryDocument>?
    @ObservationIgnored private let libraryFile: FlixJSONFile<FlixLibraryDocument>?
    /// Called after every change, for the dock tiles and the menu bar item.
    @ObservationIgnored var didChange: (() -> Void)?

    /// Newest first.
    var items: [FlixItem] { document.items }
    var favorites: [FlixFavorite] { library.favorites }
    var smartFilters: [FlixSmartFilter] { library.smartFilters }

    /// - Parameter folder: Where `history.json` and `library.json` live. Nil keeps everything in
    ///   memory, for previews and tests.
    init(folder: URL?, document: FlixHistoryDocument = FlixHistoryDocument(),
         library: FlixLibraryDocument = FlixLibraryDocument()) {
        historyFile = folder.map { FlixJSONFile(url: $0.appending(path: "history.json")) }
        libraryFile = folder.map { FlixJSONFile(url: $0.appending(path: "library.json")) }
        self.document = document
        self.library = library
    }

    /// The live history in DOKK's Application Support folder.
    static func live() -> FlixHistory {
        FlixHistory(folder: FlixStorageLocation.folder())
    }

    /// Reads the saved files. Call once at start-up; it reads synchronously because the files are
    /// small (a few hundred kilobytes at the 5,000-item cap) and the tile needs them at once.
    func load() {
        do {
            if let saved = try historyFile?.load() { document = saved }
        } catch {
            historyFile?.quarantine()
            recoveredFromUnreadableFile = true
        }
        do {
            if let saved = try libraryFile?.load() { library = saved }
        } catch {
            libraryFile?.quarantine()
            recoveredFromUnreadableFile = true
        }
        didChange?()
    }

    /// Writes pending changes now, for quit.
    func flush() {
        historyFile?.flush()
        libraryFile?.flush()
    }

    // MARK: - Items

    /// Merges what a source saw. See ``FlixHistoryDocument/record(_:)`` for the rules.
    func record(_ event: FlixActivityEvent) {
        guard document.record(event) else { return }
        saveHistory()
    }

    /// Merges a batch with one save, for Spotlight's first gather.
    func record(_ events: [FlixActivityEvent]) {
        var changed = false
        for event in events where document.record(event) { changed = true }
        if changed { saveHistory() }
    }

    func item(_ id: FlixItem.ID) -> FlixItem? { document.items.first { $0.id == id } }

    /// Removes items from Flix Files only. Returns what was removed, for Undo.
    @discardableResult
    func remove(_ ids: Set<FlixItem.ID>) -> [FlixItem] {
        let removed = document.items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        document.remove(ids)
        saveHistory()
        return removed
    }

    func restore(_ items: [FlixItem]) {
        guard !items.isEmpty else { return }
        document.restore(items)
        saveHistory()
    }

    /// Drops items whose files no longer exist.
    func forget(_ ids: Set<FlixItem.ID>) {
        guard !ids.isEmpty else { return }
        document.forget(ids)
        saveHistory()
    }

    func setFlagged(_ flagged: Bool, for ids: Set<FlixItem.ID>) {
        document.setFlagged(flagged, for: ids)
        saveHistory()
    }

    func relocate(_ id: FlixItem.ID, to path: String, name: String) {
        document.relocate(id, to: path, name: name)
        saveHistory()
    }

    /// Items that arrived since the panel was last opened.
    func unseenCount(hidingNoise: Bool) -> Int { document.unseenCount(hidingNoise: hidingNoise) }

    /// Clears the unseen badge. Called when the panel opens.
    func markSeen(at date: Date = .now) {
        guard document.lastSeen < date else { return }
        document.lastSeen = date
        saveHistory()
    }

    /// The newest item the tile shows and drags, noise excluded when hidden.
    func newest(hidingNoise: Bool) -> FlixItem? {
        document.items.first { !(hidingNoise && FlixNoiseRules.isNoise(path: $0.path)) }
    }

    /// Forgets every item. The library stays.
    func clear() {
        document = FlixHistoryDocument()
        document.lastSeen = .now
        saveHistory()
    }

    // MARK: - Library

    func addFavorite(_ favorite: FlixFavorite) {
        guard !library.favorites.contains(where: { $0.path == favorite.path }) else { return }
        library.favorites.append(favorite)
        saveLibrary()
    }

    func removeFavorite(_ id: FlixFavorite.ID) {
        library.favorites.removeAll { $0.id == id }
        saveLibrary()
    }

    /// Moves a favorite to `index` in the list with it removed.
    func moveFavorite(_ id: FlixFavorite.ID, to index: Int) {
        guard let source = library.favorites.firstIndex(where: { $0.id == id }) else { return }
        let favorite = library.favorites.remove(at: source)
        library.favorites.insert(favorite, at: min(max(0, index), library.favorites.count))
        saveLibrary()
    }

    func saveSmartFilter(_ filter: FlixSmartFilter) {
        if let index = library.smartFilters.firstIndex(where: { $0.id == filter.id }) {
            library.smartFilters[index] = filter
        } else {
            library.smartFilters.append(filter)
        }
        saveLibrary()
    }

    func removeSmartFilter(_ id: FlixSmartFilter.ID) {
        library.smartFilters.removeAll { $0.id == id }
        saveLibrary()
    }

    // MARK: - Persistence

    private func saveHistory() {
        historyFile?.schedule(document)
        didChange?()
    }

    private func saveLibrary() {
        libraryFile?.schedule(library)
        didChange?()
    }
}
