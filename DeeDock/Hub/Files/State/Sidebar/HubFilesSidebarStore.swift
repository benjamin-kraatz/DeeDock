import AppKit
import Observation

/// The Files sidebar's Favorites list: its order, where each added folder is now, and persistence
/// under `hub.files.sidebar.v1`.
///
/// One list serves the whole app; it doesn't depend on the display the Hub opens on. Added folders
/// are stored as bookmarks, so a folder renamed or moved in Finder keeps its row. Resolution runs
/// off the main actor on `VolumeReads`, because a stat on an unreachable share can block: at
/// launch, when the Files tab appears (at most every couple of seconds), after an add, and when a
/// volume mounts, unmounts, or is renamed.
@MainActor @Observable
final class HubFilesSidebarStore {
    /// A removed row and where it was, so Undo can put it back.
    struct Removal: Equatable {
        let entry: HubFilesSidebarEntry
        let index: Int
    }

    /// The Favorites rows in order.
    private(set) var entries: [HubFilesSidebarEntry]
    /// The latest resolution of each added folder. A folder without one is treated as available
    /// at its stored path until its first resolution lands.
    private(set) var resolutions: [UUID: HubFilesSidebarResolution] = [:]

    /// The home folder that places resolve against.
    let home: URL

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let resolver: any HubFilesSidebarResolving
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var volumeObservers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - observesVolumes: Re-resolve on mount, unmount, and volume rename. Off for previews and tests.
    init(defaults: UserDefaults, home: URL, resolver: any HubFilesSidebarResolving, observesVolumes: Bool) {
        self.defaults = defaults
        self.home = HubFilesPath.normalized(home)
        self.resolver = resolver
        entries = HubFilesSidebarSnapshot.load(from: defaults)
        if observesVolumes { observeVolumes() }
        refresh(force: true)
    }

    isolated deinit {
        refreshTask?.cancel()
        volumeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    // MARK: Queries

    func index(of id: HubFilesSidebarEntryID) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    func entry(_ id: HubFilesSidebarEntryID) -> HubFilesSidebarEntry? {
        index(of: id).map { entries[$0] }
    }

    /// Where an added folder is: available until its first resolution says otherwise.
    func status(of folder: HubFilesSidebarFolder) -> HubFilesSidebarResolution.Status {
        resolutions[folder.id]?.status ?? .available
    }

    /// The folder a row opens and accepts drops into. Nil for Recents and for a missing or
    /// disconnected folder.
    func folderURL(for entry: HubFilesSidebarEntry) -> URL? {
        switch entry {
        case .place(let place):
            return place.url(home: home)
        case .folder(let folder):
            guard status(of: folder) == .available else { return nil }
            return currentURL(of: folder)
        }
    }

    /// What a click on the row shows, or nil when the folder can't be opened.
    func location(for entry: HubFilesSidebarEntry) -> HubFilesLocation? {
        if case .place(let place) = entry { return place.location(home: home) }
        return folderURL(for: entry).map(HubFilesLocation.folder(normalizing:))
    }

    /// The row's title: the place's name, or the folder's display name.
    func title(for entry: HubFilesSidebarEntry) -> String {
        switch entry {
        case .place(let place): place.title(home: home)
        case .folder(let folder): resolutions[folder.id]?.name ?? folder.url.lastPathComponent
        }
    }

    /// Where an added folder is now, or where it was last seen.
    func currentURL(of folder: HubFilesSidebarFolder) -> URL {
        resolutions[folder.id]?.url ?? folder.url
    }

    /// The row for `url`: the place whose folder it is, or an added folder that resolves there.
    func entryID(for url: URL) -> HubFilesSidebarEntryID? {
        if let place = HubFilesPlace.place(for: url, home: home), index(of: .place(place)) != nil {
            return .place(place)
        }
        for case .folder(let folder) in entries where HubFilesPath.same(currentURL(of: folder), url) {
            return .folder(folder.id)
        }
        return nil
    }

    /// Built-in places that were removed, in their default order.
    var missingPlaces: [HubFilesPlace] {
        HubFilesPlace.allCases.filter { index(of: .place($0)) == nil }
    }

    // MARK: Changes

    /// Adds folders at `index` as one drop or one command, in the given order.
    ///
    /// A folder already in the list moves to `index` instead of appearing twice. The folder of a
    /// removed built-in place comes back as that place, with its name and symbol.
    /// - Returns: The rows now holding `urls`, and the subset that is new to the list.
    @discardableResult
    func insert(_ urls: [URL], at index: Int) -> (ids: [HubFilesSidebarEntryID], added: [HubFilesSidebarEntryID]) {
        var placed: [HubFilesSidebarEntry] = []
        var added: [HubFilesSidebarEntryID] = []
        for url in urls.map(HubFilesPath.normalized) {
            let entry: HubFilesSidebarEntry
            if let id = entryID(for: url), let existing = self.entry(id) {
                entry = existing
            } else if let place = HubFilesPlace.place(for: url, home: home) {
                entry = .place(place)
                added.append(entry.id)
            } else {
                entry = .folder(HubFilesSidebarFolder(path: FilePathCopy.path(of: url)))
                added.append(entry.id)
            }
            guard !placed.contains(where: { $0.id == entry.id }) else { continue }
            placed.append(entry)
        }
        guard !placed.isEmpty else { return ([], []) }
        var target = max(0, min(index, entries.count))
        for entry in placed {
            guard let current = self.index(of: entry.id) else { continue }
            entries.remove(at: current)
            if current < target { target -= 1 }
        }
        entries.insert(contentsOf: placed, at: target)
        save()
        // New folders have no bookmark yet; resolving creates one.
        if !added.isEmpty { refresh(force: true) }
        return (placed.map(\.id), added)
    }

    /// Moves a row so it sits before the row now at `index`, or last when `index` is the count.
    func move(_ id: HubFilesSidebarEntryID, to index: Int) {
        guard let from = self.index(of: id) else { return }
        let target = min(max(index > from ? index - 1 : index, 0), entries.count - 1)
        guard target != from else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: target)
        save()
    }

    /// Removes a row. Its resolution is kept so Undo restores it as it was.
    @discardableResult
    func remove(_ id: HubFilesSidebarEntryID) -> Removal? {
        guard let index = index(of: id) else { return nil }
        let entry = entries.remove(at: index)
        save()
        return Removal(entry: entry, index: index)
    }

    /// Puts a removed row back where it was. Does nothing if it is back already.
    func restore(_ removal: Removal) {
        guard index(of: removal.entry.id) == nil else { return }
        entries.insert(removal.entry, at: min(removal.index, entries.count))
        save()
    }

    /// Puts every removed built-in place back in its default position and keeps added folders.
    ///
    /// A place returns right after the last place that precedes it by default, or first.
    /// - Returns: The places that came back.
    @discardableResult
    func restoreDefaultPlaces() -> [HubFilesPlace] {
        let missing = missingPlaces
        for place in missing {
            let predecessors = HubFilesPlace.allCases.prefix { $0 != place }
            let anchor = entries.lastIndex { entry in
                if case .place(let other) = entry { predecessors.contains(other) } else { false }
            }
            entries.insert(.place(place), at: anchor.map { $0 + 1 } ?? 0)
        }
        if !missing.isEmpty { save() }
        return missing
    }

    // MARK: Resolution

    /// Re-resolves every added folder off the main actor. A newer refresh supersedes an older one.
    ///
    /// - Parameter force: Skip the throttle that keeps repeated tab appearances from re-reading.
    func refresh(force: Bool = false) {
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 2 { return }
        lastRefresh = .now
        let folders = entries.compactMap { entry -> HubFilesSidebarFolder? in
            if case .folder(let folder) = entry { folder } else { nil }
        }
        refreshTask?.cancel()
        guard !folders.isEmpty else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let resolver = resolver
        refreshTask = Task { [weak self] in
            let results = await VolumeReads.run(qos: .utility) {
                folders.map { ($0.id, resolver.resolve($0)) }
            }
            guard !Task.isCancelled, let self, self.refreshGeneration == generation else { return }
            self.apply(results)
        }
    }

    /// Stores new resolutions, and follows renamed or moved folders by updating their stored path
    /// and bookmark.
    private func apply(_ results: [(UUID, HubFilesSidebarResolution)]) {
        var changed = false
        for (id, resolution) in results {
            if resolutions[id] != resolution { resolutions[id] = resolution }
            guard let index = index(of: .folder(id)), case .folder(var folder) = entries[index] else { continue }
            var updated = false
            let path = FilePathCopy.path(of: resolution.url)
            if resolution.status == .available, path != folder.path {
                folder.path = path
                updated = true
            }
            if let bookmark = resolution.refreshedBookmark, bookmark != folder.bookmark {
                folder.bookmark = bookmark
                updated = true
            }
            if updated {
                entries[index] = .folder(folder)
                changed = true
            }
        }
        if changed { save() }
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification]
        volumeObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(force: true) }
            }
        }
    }

    private func save() {
        HubFilesSidebarSnapshot(entries: entries).save(to: defaults)
    }
}
