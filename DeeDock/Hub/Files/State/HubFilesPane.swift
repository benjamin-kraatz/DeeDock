import Foundation
import Observation

/// One file browser pane: a location with history, a sorted listing kept live while visible,
/// and a selection.
///
/// A pane loads and watches its folder only while `isActive` (it is visible in the selected
/// browser tab of a shown Hub). Each reload cancels the previous one, and a generation counter
/// drops results that arrive after the location changed.
@MainActor @Observable
final class HubFilesPane: Identifiable {
    /// The listing's loading state.
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// The folder exists but could not be read (usually a privacy permission).
        case failed(String)
    }

    let id = UUID()
    private(set) var location: HubFilesLocation
    private(set) var backStack: [HubFilesLocation] = []
    private(set) var forwardStack: [HubFilesLocation] = []

    /// The pane's sort. Setting it re-sorts in place and persists.
    var sort: HubFileSort {
        didSet {
            guard sort != oldValue else { return }
            folderItems = sort.sorted(folderItems)
            columnItems = columnItems.mapValues(sort.sorted)
            onPersistentChange?()
        }
    }

    private(set) var folderItems: [HubFileItem] = []
    /// Listings of the column view's ancestor folders, keyed by normalized folder path.
    private(set) var columnItems: [String: [HubFileItem]] = [:]
    private(set) var loadState: LoadState = .idle
    /// Free space on the current folder's volume, for the status bar.
    private(set) var availableBytes: Int64?
    var selection = HubFilesSelection()
    /// The item showing an inline rename field, if any.
    private(set) var renamingURL: URL?
    /// The rename field's text. Lives here so keyboard handling can commit it.
    var renameDraft = ""
    /// Paths of items that just arrived; rows flash green while their path is here.
    private(set) var freshPaths: Set<String> = []
    /// Bumped with the URL to scroll to after keyboard selection; views scroll on change.
    private(set) var scrollRequest: HubFilesScrollRequest?

    /// Items per row in icon view, reported by the view for arrow-key movement.
    @ObservationIgnored var iconColumns = 1
    /// True while the owning tab shows columns; the pane then also lists ancestor folders.
    @ObservationIgnored var showsColumns = false {
        didSet { if showsColumns != oldValue, showsColumns { reload() } }
    }
    /// Called after the location or sort changes, so the model can persist.
    @ObservationIgnored var onPersistentChange: (() -> Void)?
    /// Called when the shown folder no longer exists (deleted or its volume unmounted).
    @ObservationIgnored var onLocationVanished: ((HubFilesPane) -> Void)?
    /// Called when the selection changes, so Quick Look can follow it.
    @ObservationIgnored var onSelectionChange: (() -> Void)?

    @ObservationIgnored private let dataSource: HubFilesDataSource
    @ObservationIgnored private let anchors: [URL]
    @ObservationIgnored private(set) var isActive = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var freshTask: Task<Void, Never>?
    @ObservationIgnored private var watch: HubFilesWatch?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingSelectionPaths: [String] = []
    @ObservationIgnored private var scrollSerial = 0

    private static let historyLimit = 50

    /// - Parameters:
    ///   - anchors: Folders where breadcrumbs and the column view start (sidebar places).
    init(location: HubFilesLocation, sort: HubFileSort = HubFileSort(), dataSource: HubFilesDataSource, anchors: [URL]) {
        self.location = location
        self.sort = sort
        self.dataSource = dataSource
        self.anchors = anchors
    }

    isolated deinit {
        loadTask?.cancel()
        freshTask?.cancel()
        watch?.stop()
    }

    // MARK: Listing

    /// The items the pane shows, in display order.
    ///
    /// Recents keep Spotlight's newest-first order under the default name sort, because an
    /// alphabetical Recents list hides what was used last; any other sort applies as chosen.
    var items: [HubFileItem] {
        guard location == .recents else { return folderItems }
        let recents = dataSource.recentItems
        return sort.key == .name && sort.ascending ? recents : sort.sorted(recents)
    }

    /// Item URLs in display order, for selection ranges and arrow keys.
    var orderedURLs: [URL] { items.map(\.url) }

    /// The selected items in display order.
    var selectedItems: [HubFileItem] {
        selection.isEmpty ? [] : items.filter { selection.contains($0.url) }
    }

    /// The folder's URL, or nil for Recents.
    var folderURL: URL? { location.folderURL }

    /// Folders from the nearest sidebar anchor to the current folder: breadcrumbs and columns.
    var pathChain: [URL] {
        guard let folder = folderURL else { return [] }
        return HubFilesPath.chain(to: folder, anchors: anchors)
    }

    /// The items of one column-view folder. The last column is the current listing.
    func columnListing(for folder: URL) -> [HubFileItem] {
        if let current = folderURL, HubFilesPath.same(current, folder) { return folderItems }
        return columnItems[FilePathCopy.path(of: folder)] ?? []
    }

    /// True while `item` shows the inline rename field.
    func isRenaming(_ item: HubFileItem) -> Bool {
        renamingURL.map { HubFilesPath.same($0, item.url) } ?? false
    }

    /// Shows the rename field for `url`, prefilled with its current name.
    func beginRename(_ url: URL, name: String) {
        renamingURL = url
        renameDraft = name
    }

    /// Hides the rename field.
    func endRename() {
        renamingURL = nil
        renameDraft = ""
    }

    func isFresh(_ item: HubFileItem) -> Bool {
        !freshPaths.isEmpty && freshPaths.contains(FilePathCopy.path(of: item.url))
    }

    // MARK: Activation

    /// Starts or stops loading and watching. Only visible panes are active.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startWatching()
            reload()
        } else {
            stopWatching()
            loadTask?.cancel()
            loadTask = nil
        }
    }

    /// Reads the folder (and, in column view, its ancestors) again. Does nothing while inactive.
    func reload() {
        guard isActive else { return }
        loadTask?.cancel()
        generation += 1
        let generation = generation
        guard let folder = folderURL else {
            loadState = .loaded
            selection.prune(to: orderedURLs)
            return
        }
        if folderItems.isEmpty { loadState = .loading }
        let ancestors = showsColumns ? pathChain.dropLast() : []
        loadTask = Task { [weak self, dataSource] in
            do {
                let listed = try await dataSource.items(in: folder)
                guard let self, generation == self.generation else { return }
                self.apply(listed)
                var columns: [String: [HubFileItem]] = [:]
                for ancestor in ancestors {
                    if let items = try? await dataSource.items(in: ancestor) {
                        columns[FilePathCopy.path(of: ancestor)] = self.sort.sorted(items)
                    }
                }
                let available = await dataSource.availableCapacity(for: folder)
                guard generation == self.generation else { return }
                self.columnItems = columns
                self.availableBytes = available
            } catch is CancellationError {
            } catch {
                guard let self, generation == self.generation else { return }
                if dataSource.directoryExists(folder) {
                    self.folderItems = []
                    self.loadState = .failed(error.localizedDescription)
                } else {
                    self.onLocationVanished?(self)
                }
            }
        }
    }

    private func apply(_ listed: [HubFileItem]) {
        folderItems = sort.sorted(listed)
        loadState = .loaded
        let order = folderItems.map(\.url)
        selection.prune(to: order)
        if let renamingURL, !folderItems.contains(where: { HubFilesPath.same($0.url, renamingURL) }),
           pendingSelectionPaths.isEmpty {
            self.renamingURL = nil
        }
        if !pendingSelectionPaths.isEmpty {
            let matches = folderItems.filter { pendingSelectionPaths.contains(FilePathCopy.path(of: $0.url)) }
            if !matches.isEmpty {
                selection.set(matches.map(\.url))
                pendingSelectionPaths = []
                requestScroll(to: matches[0].url)
                onSelectionChange?()
            }
        }
    }

    private func startWatching() {
        stopWatching()
        guard isActive, let folder = folderURL else { return }
        watch = dataSource.watch(folder) { [weak self] in self?.reload() }
    }

    private func stopWatching() {
        watch?.stop()
        watch = nil
    }

    // MARK: Navigation

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoToParent: Bool { folderURL.flatMap(HubFilesPath.parent(of:)) != nil }

    /// Shows `location`, pushing the current one onto the back stack and clearing forward history.
    func navigate(to location: HubFilesLocation) {
        guard location != self.location else { return }
        backStack.append(self.location)
        if backStack.count > Self.historyLimit { backStack.removeFirst() }
        forwardStack = []
        show(location)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        show(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        show(next)
    }

    /// Opens the enclosing folder and selects the folder just left, like Finder's ⌘↑.
    func goToParent() {
        guard let folder = folderURL, let parent = HubFilesPath.parent(of: folder) else { return }
        navigate(to: .folder(normalizing: parent))
        pendingSelectionPaths = [FilePathCopy.path(of: folder)]
    }

    /// Replaces the location without touching history; used for fallbacks (deleted folder,
    /// ejected volume), where going back would only fail again.
    func replaceLocation(with location: HubFilesLocation) {
        backStack.removeAll { $0 == location }
        show(location)
    }

    /// Selects the items at `paths` once they appear in the listing (after a reveal, a new
    /// folder, or a rename).
    func selectWhenListed(_ urls: [URL]) {
        pendingSelectionPaths = urls.map(FilePathCopy.path(of:))
        apply(folderItems)
    }

    private func show(_ location: HubFilesLocation) {
        self.location = location
        selection.clear()
        renamingURL = nil
        pendingSelectionPaths = []
        folderItems = []
        columnItems = [:]
        availableBytes = nil
        loadState = .idle
        startWatching()
        reload()
        onPersistentChange?()
        onSelectionChange?()
    }

    // MARK: Selection

    /// Applies a click on an item.
    func click(_ url: URL, mode: HubFilesSelection.ClickMode) {
        selection.click(url, mode: mode, order: orderedURLs)
        onSelectionChange?()
    }

    /// Moves the keyboard cursor and scrolls to it.
    func moveSelection(by delta: Int, extending: Bool) {
        if let url = selection.move(by: delta, order: orderedURLs, extending: extending) {
            requestScroll(to: url)
            onSelectionChange?()
        }
    }

    func selectAll() {
        selection.selectAll(orderedURLs)
        onSelectionChange?()
    }

    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection.clear()
        onSelectionChange?()
    }

    private func requestScroll(to url: URL) {
        scrollSerial += 1
        scrollRequest = HubFilesScrollRequest(url: url, serial: scrollSerial)
    }

    // MARK: Fresh items

    /// Flashes the items at `urls` green for 2.4 s when they appear, as after a copy lands.
    func markFresh(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        freshPaths.formUnion(urls.map(FilePathCopy.path(of:)))
        freshTask?.cancel()
        freshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.freshPaths = []
        }
    }
}

/// A request to scroll an item into view. The serial makes repeated requests for the same item
/// distinct, so `onChange` fires each time.
struct HubFilesScrollRequest: Equatable {
    let url: URL
    let serial: Int
}
