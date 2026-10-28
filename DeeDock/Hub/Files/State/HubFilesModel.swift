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
    /// Selection within the Spotlight name results. Empty while a Lookout hit is selected (`lookoutSelection`).
    var searchSelection = HubFilesSelection()
    /// The selected Lookout hit's path (`LookoutHit.id`), or nil. One selection spans both result sections: selecting
    /// a Lookout hit clears `searchSelection`, and selecting a name clears this (`HubFilesModel+Lookout`).
    var lookoutSelection: String?
    /// Whether the "Weaker matches" fold under Lookout's results is open. It closes again for every new query.
    var lookoutWeakExpanded = false
    /// Progress of Lookout's model download, 0…1, for the Lookout section's download card and the status chip; nil
    /// while nothing downloads. `LookoutModelDownloader` sets it (`HubCoordinator.configureLookout`).
    var lookoutDownloadProgress: Double?
    /// The drop target under an in-flight drag, for the accent highlight.
    var dropHighlight: HubFilesDropHighlight?
    /// A failed file operation's message, shown as an alert.
    var errorMessage: String?
    /// Search results scroll request after arrow keys.
    var searchScrollRequest: HubFilesSearchScrollRequest?
    /// The picture the search field searches with, and the words from before it (`HubFilesModel+Pictures`).
    var pictureSession = LookoutPictureSession()
    /// Which groups' "Weaker matches" folds are open in a search with a picture. They close for every new picture.
    var pictureWeakExpanded: Set<LookoutSimilarResults.GroupKind> = []
    /// The search field's drop well while something is dragged over the Hub.
    var pictureDropState: HubSearchDropState = .none
    /// True while a drag the field takes is right over it.
    var isPictureDropTargeted = false
    /// Whether the index holds a vector for a file, by path, as Find Similar checks name results, browser files and
    /// dragged documents.
    var similarIndexed: [String: Bool] = [:]

    // MARK: Services

    let dataSource: HubFilesDataSource
    let transfers: HubFileTransferQueue
    let volumes: HubVolumes
    let search: HubFileSearch
    /// Lookout, the content search. Its results show in their own section under `search`'s names, which never wait
    /// for it. The tab also tells it when it appears and hides, which warms and releases what it keeps in memory
    /// (inert while Lookout is off).
    let lookout: LookoutEngine
    /// "Set up Lookout" in the search results' promo card, and the status chip while Lookout isn't set up: opens
    /// Lookout's onboarding over the Hub (`HubCoordinator.presentLookoutSetup`).
    @ObservationIgnored var onSetUpLookout: () -> Void = {}
    /// The status chip once Lookout is set up: routes Settings to Lookout's section (`DockCoordinator`). The view
    /// that calls it opens the Settings window (`openLookoutSettings(using:)`).
    @ObservationIgnored var onOpenLookoutSettings: () -> Void = {}
    /// The sidebar's Favorites list and its drag, feedback, and Undo state.
    let sidebar: HubFilesSidebarModel
    @ObservationIgnored let quickLook = HubFilesQuickLook()
    @ObservationIgnored private(set) weak var shell: HubShell?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) var isVisible = false
    @ObservationIgnored private var recentsActive = false
    @ObservationIgnored var searchSerial = 0
    /// The current search session has been counted for analytics (`endLookoutSearchSession`).
    @ObservationIgnored var lookoutSearchCounted = false
    /// The `didUnmountNotification` observer, registered while the tab is visible.
    @ObservationIgnored private var unmountObserver: NSObjectProtocol?
    @ObservationIgnored var dropOperationCache: (key: String, operation: NSDragOperation)?
    /// Whether a drag is over the Hub, for the drop well.
    @ObservationIgnored let pictureDrag = HubFilesPictureDrag()
    /// Asks the index whether a dragged document is in it, while the drag is over the Hub; cancelled when the drop
    /// well closes (`HubFilesModel+Pictures`).
    @ObservationIgnored var dragLookup: Task<Void, Never>?
    /// True while the model itself sets `query` for a picture, so the change isn't taken for typing.
    @ObservationIgnored var settingQueryForPicture = false
    /// The picture the picture search last started with, so a scope change or reappearing reuses its vector.
    @ObservationIgnored var searchedPictureID: UUID?

    /// Values that replace live service state in previews.
    @ObservationIgnored var previewOverrides = HubFilesPreviewOverrides()

    /// Creates the model with live services, restoring the last layout from `defaults`.
    ///
    /// - Parameter lookout: The app's one Lookout engine; nil makes an inert one (previews and tests).
    convenience init(defaults: UserDefaults = .standard, lookout: LookoutEngine? = nil) {
        self.init(defaults: defaults, dataSource: HubFilesLiveDataSource(), lookout: lookout)
    }

    /// Creates the model with an injected data source (previews and tests).
    init(defaults: UserDefaults,
         dataSource: HubFilesDataSource,
         transfers: HubFileTransferQueue = HubFileTransferQueue(),
         volumes: HubVolumes = HubVolumes(),
         search: HubFileSearch = HubFileSearch(),
         lookout: LookoutEngine? = nil) {
        self.defaults = defaults
        self.dataSource = dataSource
        self.transfers = transfers
        self.volumes = volumes
        self.search = search
        self.lookout = lookout ?? .inert()
        let home = dataSource.homeDirectory
        sidebar = HubFilesSidebarModel(store: HubFilesSidebarStore(
            defaults: defaults, home: home, resolver: dataSource.makeSidebarResolver(),
            observesVolumes: dataSource.observesVolumes))
        let snapshot = HubFilesSnapshot.load(from: defaults) ?? .firstRun(home: home)
        showsPreview = snapshot.showsPreview
        selectedTabID = UUID()
        tabs = snapshot.tabs.map(makeTab)
        selectedTabID = tabs[min(max(snapshot.selectedTab, 0), tabs.count - 1)].id
        configureQuickLook()
        sidebar.files = self
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

    /// True while a non-empty query, or a picture to search with (with or without words), shows search results instead
    /// of panes.
    var isSearching: Bool { !trimmedQuery.isEmpty || pictureSession.isActive }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Shell entry points

    /// Shows `folder` in the active pane of the selected tab and clears any search.
    func open(folder: URL) {
        endSearch()
        activePane.navigate(to: .folder(normalizing: folder))
        refreshActivation()
    }

    /// Opens `url`'s enclosing folder in the active pane and selects it.
    func reveal(_ url: URL) {
        endSearch()
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
        if isSearching {
            lookoutSearchCounted = false
            runSearch()
        }
        lookout.hubFilesDidAppear()
        // Folders renamed or moved in Finder since the last look keep their sidebar rows.
        sidebar.store.refresh()
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
        sidebar.endItemDrag()
        sidebar.abortReorder()
        sidebar.cancelFlights()
        sidebar.problem = nil
        volumes.stop()
        endLookoutSearchSession()
        search.stop()
        lookout.search.stop()
        lookout.hubDidClose()
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

    /// A middle click on a folder: selects the browser tab that already shows `location`, or opens
    /// a new tab showing it, like a link middle-clicked in a web browser. Clears any search.
    ///
    /// Any visible pane counts as showing the location. The selected tab is checked first, so a
    /// split pane next to the click wins over another tab; the matching pane becomes active. A new
    /// tab copies the active pane's sort and the tab's view mode and starts without back history.
    ///
    /// With `inBackground` (Shift-middle-click) nothing on screen changes: the selected tab, its
    /// panes, and any search stay as they are, a new tab is added at the end of the strip without
    /// being selected, and a location some tab already shows opens nothing.
    func showInTab(_ location: HubFilesLocation, inBackground: Bool = false) {
        let existing = tabShowing(location)
        if inBackground {
            guard existing == nil else { return }
            // The new tab's pane stays inactive (unloaded) until its tab is selected.
            tabs.append(makeTab(showing: location))
            persist()
            return
        }
        endSearch()
        cancelRenames()
        if let (tab, paneIndex) = existing {
            selectedTabID = tab.id
            if tab.isSplit { tab.activePaneIndex = paneIndex }
        } else {
            let tab = makeTab(showing: location)
            tabs.append(tab)
            selectedTabID = tab.id
        }
        refreshActivation()
        quickLook.selectionDidChange()
        persist()
    }

    /// A single-pane tab at `location` with the selected tab's view mode and active pane's sort.
    private func makeTab(showing location: HubFilesLocation) -> HubFilesBrowserTab {
        let current = selectedTab
        let pane = makePane(location: location, sort: current.activePane.sort)
        return HubFilesBrowserTab(panes: [pane], isSplit: false, activePaneIndex: 0, viewMode: current.viewMode)
    }

    /// The tab and pane index showing `location` in a visible pane, checking the selected tab and
    /// its active pane first. Folders compare by path, so a listing's trailing slash still matches.
    private func tabShowing(_ location: HubFilesLocation) -> (HubFilesBrowserTab, Int)? {
        func shows(_ pane: HubFilesPane) -> Bool {
            switch (pane.location, location) {
            case (.recents, .recents): true
            case (.folder(let shown), .folder(let wanted)): HubFilesPath.same(shown, wanted)
            default: false
            }
        }
        let selected = selectedTab
        let ordered = [selected] + tabs.filter { $0.id != selected.id }
        for tab in ordered {
            let indices = tab.visiblePanes.indices
            let active = tab.isSplit ? tab.activePaneIndex : 0
            if let index = ([active] + indices.filter { $0 != active }).first(where: { shows(tab.panes[$0]) }) {
                return (tab, index)
            }
        }
        return nil
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

    /// Shows a location in the right pane, enabling split view and giving it keyboard input.
    /// Preserves the left pane and reuses the right pane's independent navigation history.
    /// Clears search and persists the resulting layout, including when split was already on.
    func openInRightSplit(_ location: HubFilesLocation) {
        let tab = selectedTab
        cancelRenames()
        query = ""
        tab.ensureSecondPane { makePane(location: location, sort: HubFileSort()) }
        tab.isSplit = true
        tab.activePaneIndex = 1
        tab.panes[1].navigate(to: location)
        refreshActivation()
        quickLook.selectionDidChange()
        persist()
    }

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
        endSearch()
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

    /// Ends the search before the panes navigate: the words, and a picture searched with. Clearing the words alone
    /// leaves a picture search showing over the panes, because its field is already empty (`queryDidChange` never
    /// runs), so the picture goes first.
    private func endSearch() {
        if pictureSession.isActive { removePicture(restoringWords: false) }
        query = ""
    }

    private func queryDidChange(from oldValue: String) {
        // The model replacing the words for a picture runs `searchDidChange` itself.
        guard !settingQueryForPicture else { return }
        // Words typed after the picture's chip search together with it.
        if pictureSession.isActive {
            pictureWordsDidChange()
            return
        }
        searchDidChange(wasSearching: !oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// The search changed (new words, a picture, or neither): switches between panes and results when that changed,
    /// resets the selection and the folds, and searches again.
    func searchDidChange(wasSearching: Bool) {
        if wasSearching != isSearching {
            cancelRenames()
            quickLook.close()
            refreshActivation()
            // Lookout still shows the old query's results here: count the search that ends, before they're cleared.
            if wasSearching { endLookoutSearchSession() } else { lookoutSearchCounted = false }
        }
        searchSelection.clear()
        lookoutSelection = nil
        lookoutWeakExpanded = false
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

    /// Starts Spotlight's name search and Lookout's content search for the query, side by side: the names never wait
    /// for Lookout. Both stop while the tab is hidden; an empty query also clears Lookout's results.
    private func runSearch() {
        guard previewOverrides.searchResults == nil, previewOverrides.pictureResults == nil else { return }
        if let picture = pictureSession.picture {
            // A picture lists no names and runs no search by words.
            search.stop()
            lookout.search.search("", scope: resolvedSearchScope)
            if isVisible { runPictureSearch(picture) }
            return
        }
        guard isVisible, isSearching else {
            search.stop()
            if isSearching { lookout.search.stop() } else { lookout.search.search("", scope: resolvedSearchScope) }
            return
        }
        search.search(trimmedQuery, scope: resolvedSearchScope)
        lookout.search.search(trimmedQuery, scope: resolvedSearchScope)
    }

    /// Search results in display order.
    var searchResults: [HubFileItem] { previewOverrides.searchResults ?? search.results }

    /// A click on a name result. Moves the selection out of the Lookout section.
    func clickSearchResult(_ url: URL, mode: HubFilesSelection.ClickMode) {
        lookoutSelection = nil
        searchSelection.click(url, mode: mode, order: searchResults.map(\.url))
        quickLook.selectionDidChange()
    }

    // MARK: Selection context

    /// The items the context menu, preview, and shortcuts act on: the selected search results (a name selection or
    /// one Lookout hit) while searching, else the active pane's selection.
    var actionableItems: [HubFileItem] {
        if isSearching {
            if let hit = selectedLookoutHit { return [hit.fileItem] }
            return searchResults.filter { searchSelection.contains($0.url) }
        }
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
    /// A breadcrumb segment in one pane. Keyed by pane because split panes can show the same folder.
    case crumb(pane: UUID, folder: URL)
}

/// Service state replaced by previews, which must not touch the file system or Spotlight.
struct HubFilesPreviewOverrides {
    var searchResults: [HubFileItem]?
    var volumes: [HubVolumes.Volume]?
    var transfer: HubFilesTransferStatus?
    var finished: HubFilesTransferStatus?
    /// Lookout's status, progress, phase and results, in place of the (inert) engine's. The progress counts only
    /// with a status.
    var lookoutStatus: LookoutStatus?
    var lookoutProgress: LookoutProgressDisplay?
    var lookoutPhase: LookoutSearch.Phase?
    var lookoutResults: LookoutResultSet?
    /// A search with a picture's phase, results and reading time.
    var picturePhase: LookoutPictureSearch.Phase?
    var pictureResults: LookoutSimilarResults?
    var pictureReadSeconds: Double?
    /// The stored vector Find Similar reused, for "From your index · Page 7 · instant".
    var pictureStoredSource: LookoutSimilarSource?
    /// The picture–words slider's place, for a search with a picture and words.
    var pictureWordsWeight: Double?
}

/// Scrolls the search results to a row after arrow keys.
struct HubFilesSearchScrollRequest: Equatable {
    let id: HubFilesSearchResultID
    let serial: Int
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
