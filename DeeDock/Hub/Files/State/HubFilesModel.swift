import AppKit
import Observation

/// The Files tab: browser tabs of one or two panes, a sidebar, search, a preview column, and
/// the copy/move queue.
///
/// Owns every pane and decides which are active: only the visible panes of the selected browser
/// tab load and watch their folders, and only while the Hub shows this tab with no search
/// query. Layout and locations persist under `hub.files.v1` in the injected defaults.
@MainActor @Observable
final class HubFilesModel: HubTabModel {
    // MARK: HubTabModel

    /// The header search field's text. A non-empty query replaces the panes with search results.
    var query = "" {
        didSet { if query != oldValue { queryDidChange(from: oldValue) } }
    }

    var searchPrompt: LocalizedStringResource { .hubFilesSearchPrompt }

    // MARK: State

    private(set) var tabs: [HubFilesBrowserTab] = []
    private(set) var selectedTabID: UUID
    var showsPreview: Bool {
        didSet { if showsPreview != oldValue { persist() } }
    }
    var searchScope: HubFilesSearchScope = .thisMac {
        didSet { if searchScope != oldValue { runSearch() } }
    }
    /// Selection within search results.
    var searchSelection = HubFilesSelection()
    /// The drop target under an in-flight drag, for the accent highlight.
    var dropHighlight: HubFilesDropHighlight?
    /// A failed file operation's message, shown as an alert.
    var errorMessage: String?
    /// Search results scroll request after arrow keys.
    private(set) var searchScrollRequest: HubFilesScrollRequest?

    // MARK: Services

    let dataSource: HubFilesDataSource
    let transfers: HubFileTransferQueue
    let volumes: HubVolumes
    let search: HubFileSearch
    @ObservationIgnored let quickLook = HubFilesQuickLook()
    @ObservationIgnored private(set) weak var shell: HubShell?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) var isVisible = false
    @ObservationIgnored private var recentsActive = false
    @ObservationIgnored private var searchSerial = 0
    /// The `didUnmountNotification` observer, registered while the tab is visible.
    @ObservationIgnored private var unmountObserver: NSObjectProtocol?
    @ObservationIgnored var dropOperationCache: (key: String, operation: NSDragOperation)?

    /// Values that replace live service state in previews.
    @ObservationIgnored var previewOverrides = HubFilesPreviewOverrides()

    /// Creates the model with live services, restoring the last layout from `defaults`.
    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, dataSource: HubFilesLiveDataSource())
    }

    /// Creates the model with an injected data source (previews and tests).
    init(defaults: UserDefaults,
         dataSource: HubFilesDataSource,
         transfers: HubFileTransferQueue = HubFileTransferQueue(),
         volumes: HubVolumes = HubVolumes(),
         search: HubFileSearch = HubFileSearch()) {
        self.defaults = defaults
        self.dataSource = dataSource
        self.transfers = transfers
        self.volumes = volumes
        self.search = search
        let home = dataSource.homeDirectory
        let snapshot = HubFilesSnapshot.load(from: defaults) ?? .firstRun(home: home)
        showsPreview = snapshot.showsPreview
        selectedTabID = UUID()
        tabs = snapshot.tabs.map(makeTab)
        selectedTabID = tabs[min(max(snapshot.selectedTab, 0), tabs.count - 1)].id
        configureQuickLook()
    }

    /// Progress of the copy/move queue from 0 to 1, or nil when idle. Drives the DOKK tile ring.
    var transferProgress: Double? { transfers.overallProgress }

    var home: URL { dataSource.homeDirectory }

    /// Sidebar folders and volume roots where breadcrumbs and columns start.
    var anchors: [URL] { HubFilesPlace.anchors(home: home) }

    var selectedTab: HubFilesBrowserTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    var activePane: HubFilesPane { selectedTab.activePane }

    /// True while a non-empty query shows search results instead of panes.
    var isSearching: Bool { !trimmedQuery.isEmpty }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Shell entry points

    /// Shows `folder` in the active pane of the selected tab and clears any search.
    func open(folder: URL) {
        query = ""
        activePane.navigate(to: .folder(normalizing: folder))
        refreshActivation()
    }

    /// Opens `url`'s enclosing folder in the active pane and selects it.
    func reveal(_ url: URL) {
        query = ""
        let pane = activePane
        guard let parent = HubFilesPath.parent(of: url) else { return }
        pane.navigate(to: .folder(normalizing: parent))
        pane.selectWhenListed([url])
        refreshActivation()
    }

    func hubTabDidAppear(shell: HubShell) {
        self.shell = shell
        isVisible = true
        volumes.start()
        observeUnmounts()
        refreshActivation()
        if isSearching { runSearch() }
    }

    /// Marks the tab visible without a shell, so panes load (previews and tests).
    func activateWithoutShell() {
        isVisible = true
        refreshActivation()
    }

    func hubTabDidDisappear() {
        isVisible = false
        quickLook.close()
        cancelRenames()
        dropHighlight = nil
        volumes.stop()
        search.stop()
        if let unmountObserver { NSWorkspace.shared.notificationCenter.removeObserver(unmountObserver) }
        unmountObserver = nil
        refreshActivation()
        shell = nil
    }

    private func observeUnmounts() {
        guard unmountObserver == nil else { return }
        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.volumeDidUnmount(url) }
        }
    }

    // MARK: Tabs

    func selectTab(_ id: UUID) {
        guard id != selectedTabID, tabs.contains(where: { $0.id == id }) else { return }
        cancelRenames()
        selectedTabID = id
        refreshActivation()
        persist()
    }

    /// Adds a tab showing the active pane's location in the same view mode, and selects it.
    func newTab() {
        let current = selectedTab
        let pane = makePane(location: current.activePane.location, sort: current.activePane.sort)
        let tab = HubFilesBrowserTab(panes: [pane], isSplit: false, activePaneIndex: 0, viewMode: current.viewMode)
        tabs.append(tab)
        selectedTabID = tab.id
        refreshActivation()
        persist()
    }

    /// Closes a tab. The last tab cannot be closed.
    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].panes.forEach { $0.setActive(false) }
        tabs.remove(at: index)
        if selectedTabID == id { selectedTabID = tabs[max(0, index - 1)].id }
        refreshActivation()
        persist()
    }

    /// Display name for a tab: its active pane's location.
    func title(for tab: HubFilesBrowserTab) -> String {
        displayName(for: tab.activePane.location)
    }

    // MARK: Panes and layout

    func toggleSplit() {
        let tab = selectedTab
        cancelRenames()
        tab.ensureSecondPane { makePane(location: HubFilesPlace.downloads.location(home: home), sort: HubFileSort()) }
        tab.isSplit.toggle()
        if !tab.isSplit { tab.activePaneIndex = 0 }
        refreshActivation()
        persist()
    }

    /// Makes pane `index` of the selected tab receive keyboard input.
    func activatePane(_ index: Int) {
        let tab = selectedTab
        guard tab.isSplit, tab.panes.indices.contains(index), tab.activePaneIndex != index else { return }
        tab.activePaneIndex = index
        quickLook.selectionDidChange()
    }

    func setViewMode(_ mode: HubFilesViewMode) {
        let tab = selectedTab
        guard tab.viewMode != mode else { return }
        cancelRenames()
        tab.viewMode = mode
        Analytics.track(.hubFilesViewChanged(mode.analyticsValue))
        persist()
    }

    /// Navigates the active pane to a sidebar place and clears any search.
    func show(_ location: HubFilesLocation, in pane: HubFilesPane? = nil) {
        query = ""
        (pane ?? activePane).navigate(to: location)
        refreshActivation()
    }

    /// Location a sidebar row is highlighted for: the active pane's location.
    func isCurrent(_ location: HubFilesLocation) -> Bool {
        activePane.location == location
    }

    // MARK: Names

    @ObservationIgnored private var nameCache: [String: String] = [:]

    /// The name shown for a location in tabs, breadcrumbs, and the status bar.
    func displayName(for location: HubFilesLocation) -> String {
        guard let url = location.folderURL else { return String(localized: .hubFilesPlaceRecents) }
        return displayName(for: url)
    }

    /// Sidebar titles for places, the volume name for volume roots, else the folder's display name.
    func displayName(for url: URL) -> String {
        if let place = HubFilesPlace.place(for: url, home: home) { return place.title(home: home) }
        if let volume = driveList.first(where: { HubFilesPath.same($0.url, url) }) { return volume.name }
        let path = FilePathCopy.path(of: url)
        if let cached = nameCache[path] { return cached }
        let name = path == "/" ? FileManager.default.displayName(atPath: path) : url.lastPathComponent
        nameCache[path] = name
        return name
    }

    /// Mounted volumes for the sidebar.
    var driveList: [HubVolumes.Volume] { previewOverrides.volumes ?? volumes.volumes }

    // MARK: Activation

    /// Starts loading and watching exactly the panes on screen, and the Recents query when one
    /// of them shows Recents. Everything stops while the tab is hidden or search results show.
    func refreshActivation() {
        let showPanes = isVisible && !isSearching
        var needsRecents = false
        for tab in tabs {
            let visible = showPanes && tab.id == selectedTabID
            for pane in tab.panes {
                let active = visible && tab.visiblePanes.contains { $0 === pane }
                pane.setActive(active)
                if active, pane.location == .recents { needsRecents = true }
            }
        }
        if needsRecents != recentsActive {
            recentsActive = needsRecents
            dataSource.setRecentsActive(needsRecents)
        }
    }

    // MARK: Search

    private func queryDidChange(from oldValue: String) {
        let wasSearching = !oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if wasSearching != isSearching {
            cancelRenames()
            quickLook.close()
            refreshActivation()
        }
        searchSelection.clear()
        runSearch()
    }

    /// The search scope as the service understands it.
    var resolvedSearchScope: HubFileSearch.Scope {
        switch searchScope {
        case .thisMac: .thisMac
        case .currentFolder: .folder(searchFolder)
        }
    }

    /// The folder the "current folder" scope searches: the active pane's, or home for Recents.
    var searchFolder: URL { activePane.folderURL ?? home }

    private func runSearch() {
        guard previewOverrides.searchResults == nil else { return }
        guard isVisible, isSearching else {
            search.stop()
            return
        }
        search.search(trimmedQuery, scope: resolvedSearchScope)
    }

    /// Search results in display order.
    var searchResults: [HubFileItem] { previewOverrides.searchResults ?? search.results }

    func moveSearchSelection(by delta: Int, extending: Bool) {
        if let url = searchSelection.move(by: delta, order: searchResults.map(\.url), extending: extending) {
            searchSerial += 1
            searchScrollRequest = HubFilesScrollRequest(url: url, serial: searchSerial)
            quickLook.selectionDidChange()
        }
    }

    func clickSearchResult(_ url: URL, mode: HubFilesSelection.ClickMode) {
        searchSelection.click(url, mode: mode, order: searchResults.map(\.url))
        quickLook.selectionDidChange()
    }

    // MARK: Selection context

    /// The items the context menu, preview, and shortcuts act on: search results while
    /// searching, else the active pane's selection.
    var actionableItems: [HubFileItem] {
        if isSearching { return searchResults.filter { searchSelection.contains($0.url) } }
        return activePane.selectedItems
    }

    // MARK: Persistence

    /// Writes the current layout to `hub.files.v1`.
    func persist() {
        let snapshot = HubFilesSnapshot(
            tabs: tabs.map { tab in
                HubFilesSnapshot.Tab(
                    panes: tab.panes.map { HubFilesSnapshot.Pane(location: $0.location, sort: $0.sort) },
                    isSplit: tab.isSplit, activePane: tab.activePaneIndex, viewMode: tab.viewMode)
            },
            selectedTab: tabs.firstIndex { $0.id == selectedTabID } ?? 0,
            showsPreview: showsPreview)
        snapshot.save(to: defaults)
    }

    // MARK: Construction

    private func makeTab(_ snapshot: HubFilesSnapshot.Tab) -> HubFilesBrowserTab {
        let panes = (snapshot.panes.isEmpty ? [HubFilesSnapshot.Pane(location: .folder(home), sort: HubFileSort())] : snapshot.panes)
            .prefix(2)
            .map { makePane(location: restorable($0.location), sort: $0.sort) }
        return HubFilesBrowserTab(panes: panes, isSplit: snapshot.isSplit, activePaneIndex: snapshot.activePane,
                                  viewMode: snapshot.viewMode)
    }

    /// `location`, or home when its folder no longer exists (deleted, or its volume unmounted).
    ///
    /// Folders under /Volumes are not checked here: this runs on the main actor at launch, and a
    /// stat on a wedged network share can block. If such a folder is gone, the pane falls back
    /// home when its first load fails.
    func restorable(_ location: HubFilesLocation) -> HubFilesLocation {
        guard let url = location.folderURL else { return location }
        if FilePathCopy.path(of: url).hasPrefix("/Volumes/") { return .folder(normalizing: url) }
        return dataSource.directoryExists(url) ? .folder(normalizing: url) : .folder(home)
    }

    func makePane(location: HubFilesLocation, sort: HubFileSort) -> HubFilesPane {
        let pane = HubFilesPane(location: location, sort: sort, dataSource: dataSource, anchors: anchors)
        pane.onPersistentChange = { [weak self] in self?.persist() }
        pane.onLocationVanished = { [weak self] pane in
            guard let self else { return }
            pane.replaceLocation(with: .folder(self.home))
        }
        pane.onSelectionChange = { [weak self] in self?.quickLook.selectionDidChange() }
        return pane
    }

    private func configureQuickLook() {
        quickLook.items = { [weak self] in self?.actionableItems.map(\.url) ?? [] }
        quickLook.handleKey = { [weak self] event in
            guard let self else { return false }
            // Only selection movement; everything else stays with the panel (Space, Escape close it).
            guard let key = event.specialKey,
                  [.upArrow, .downArrow, .leftArrow, .rightArrow].contains(key) else { return false }
            return self.handleKeyDown(event, fromSearchField: false)
        }
        quickLook.setHold = { [weak self] holding in
            guard let shell = self?.shell else { return }
            if holding { shell.beginHold(.modal) } else { shell.endHold(.modal) }
        }
    }

    /// Ends every inline rename without applying it.
    func cancelRenames() {
        for tab in tabs { for pane in tab.panes where pane.renamingURL != nil { pane.endRename() } }
    }
}

/// What an in-flight drag is over, for the accent highlight.
enum HubFilesDropHighlight: Hashable {
    /// A pane's background: drops into the pane's folder.
    case pane(UUID)
    /// A folder row, tile, or column item.
    case item(URL)
    /// A sidebar place or drive.
    case sidebar(URL)
    /// A browser tab: drops into its active pane's folder.
    case tab(UUID)
    /// A column-view column: drops into that column's folder.
    case column(URL)
}

/// Service state replaced by previews, which must not touch the file system or Spotlight.
struct HubFilesPreviewOverrides {
    var searchResults: [HubFileItem]?
    var volumes: [HubVolumes.Volume]?
    var transfer: HubFilesTransferStatus?
    var finished: HubFilesTransferStatus?
}

extension HubFilesViewMode {
    var analyticsValue: AnalyticsHubFilesView {
        switch self {
        case .list: .list
        case .icons: .icons
        case .columns: .columns
        }
    }
}

extension HubFilesPlace {
    /// Sidebar title. Home shows the user's folder name, as in Finder.
    func title(home: URL) -> String {
        switch self {
        case .recents: String(localized: .hubFilesPlaceRecents)
        case .desktop: String(localized: .hubFilesPlaceDesktop)
        case .documents: String(localized: .hubFilesPlaceDocuments)
        case .downloads: String(localized: .hubFilesPlaceDownloads)
        case .home: home.lastPathComponent
        case .applications: String(localized: .hubFilesPlaceApplications)
        }
    }
}
