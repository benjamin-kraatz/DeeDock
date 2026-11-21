import AppKit
import Observation

/// Everything the open panel shows and remembers: filter, selection, search, sheets, toast, and
/// the drag in progress. One per coordinator, reset on every open.
///
/// Views read this and call its methods; commands that touch files go through `FlixFileActions`,
/// and everything that needs DOKK's other features (closing, Quick Look, the Shelf, Settings) goes
/// through the closures the coordinator sets. Main actor only.
@MainActor @Observable
final class FlixPanelState {
    let history: FlixHistory
    let intelligence: FlixIntelligence
    let settingsStore: FlixSettingsStore

    // MARK: Presentation
    var mode: FlixPanelMode = .anchored
    var phase: FlixPanelPhase = .entering
    /// Where the open spring grows from, in the content's unit space.
    var growthAnchor = FlixGrowthAnchor(x: 0.5, y: 1)
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
    /// The app and window that were in front when the panel opened.
    var frontmost: FlixFrontmostContext?
    var readPolicy = FlixReadPolicy(allowedRoots: [])
    /// Read time for relative dates and sections, refreshed while open.
    var now = Date.now

    // MARK: Content state
    var filter: FlixFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            filterChanged()
            metrics?.filterChanged(to: filter)
            reportThreadFilter()
        }
    }
    var selection: Set<FlixItem.ID> = []
    /// The row arrow keys move from and Shift-click extends from.
    var cursor: FlixItem.ID?
    var searchActive = false
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            // Before the query is cleared below, so an ending search still sees what it understood.
            metrics?.searchTextChanged(searchText)
            searchTextChanged()
        }
    }
    /// Bumped to move keyboard focus into the search field.
    var searchFocusRequest = 0
    /// Mirrors the search field's focus, so typing keys reach it instead of the list.
    var searchFieldFocused = false
    var showNoise = false
    var expandedVersions: Set<String> = []
    var sheet: FlixSheet? {
        didSet {
            // Tidy closing without Apply reports a dismissal.
            guard oldValue == .tidy, sheet != .tidy else { return }
            if !tidyApplied { reportTidyDismissed() }
            tidyApplied = false
        }
    }
    var confirmation: FlixPendingConfirmation? {
        didSet {
            // Closing the question without an answer (Cancel, a click beside it, Escape, the panel
            // closing) cancels the drag it stopped.
            guard let old = oldValue, confirmation?.id != old.id else { return }
            if !confirmationAnswered { reportWarningCancelled(old) }
            confirmationAnswered = false
        }
    }
    var toast: FlixToast?
    /// Stay open after a drag out, toggled by the header pin.
    var isPinned = false
    var drag: FlixDragActivity?
    /// A drop from another app is over the panel.
    var isDropTargeted = false
    /// The protected watched folders still waiting for an explicit **Allow…**.
    var foldersAwaitingAccess: [FlixWatchedFolder] = []
    /// Shown once per session after the access card was dismissed.
    var accessCardDismissed = false

    // MARK: Analytics
    /// The open visit's tracker (`FlixSessionMetrics`), set by the coordinator. Nil in previews.
    @ObservationIgnored weak var metrics: FlixSessionMetrics?
    /// Where the selection was last made: a press on a Fits row, or anywhere else. Keyboard commands
    /// on the selection report this place.
    @ObservationIgnored var selectionOrigin: FlixActionOrigin = .list
    /// Where Ask Robi was opened from, for the question's first-action place.
    @ObservationIgnored var robiOrigin: FlixActionOrigin?
    /// A Tidy apply waiting for its Undo window to pass, reported once it settles.
    @ObservationIgnored var pendingTidy: AnalyticsFlixTidy?
    /// Where the drag in flight (or the one a question stopped) started, for its drop report.
    @ObservationIgnored var dragOrigin: FlixActionOrigin?
    /// That drag started on the dock tile.
    @ObservationIgnored var dragFromTile = false
    /// The question on screen was answered rather than dismissed.
    @ObservationIgnored var confirmationAnswered = false
    /// The last answered drop question, for the drag that follows it.
    @ObservationIgnored var answeredWarning: FlixAnsweredWarning?
    /// The Tidy sheet on screen was applied, so its closing is not a dismissal.
    @ObservationIgnored var tidyApplied = false

    // MARK: Hooks set by the coordinator
    @ObservationIgnored var close: ((_ restoreFocus: Bool) -> Void)?
    @ObservationIgnored var toggleQuickLook: (([URL]) -> Void)?
    @ObservationIgnored var quickLookSelectionChanged: (([URL]) -> Void)?
    @ObservationIgnored var sendToShelf: (([URL]) -> Bool)?
    @ObservationIgnored var requestFolderAccess: ((String) -> Void)?
    @ObservationIgnored var prepareSettings: (() -> Void)?
    /// Records an answer to a drop question for the drag of these items and asks the next question
    /// for them, if any (`FlixCoordinator.answerDrop`). Returns true when a follow-up is showing.
    @ObservationIgnored var answerDrop: ((FlixDropConfirmation, AnalyticsFlixWarningResolution, [FlixItem.ID]) -> Bool)?
    /// Starts a native drag of items from a row's view, with where in the panel it started.
    @ObservationIgnored var beginDrag: (([FlixItem.ID], NSView, NSEvent, FlixActionOrigin) -> Void)?

    // MARK: Phase B1 (window reading, conversions, sensitive guard, web links)
    /// The page in the browser in front, for the **Save this page** card. Nil hides the card.
    var pageOffer: FlixPageOffer?
    /// Keeps ``pageOffer``'s page.
    @ObservationIgnored var savePage: (() -> Void)?
    /// A link row's "Source of …" / "↑ You sent 2 files here" line.
    @ObservationIgnored var linkRelation: ((FlixItem) -> String?)?
    /// A Fits row's "as PDF · 1.2 MB" chip, once its converted copy is ready.
    @ObservationIgnored var conversionChip: ((FlixItem) -> String?)?
    /// The sensitive question's **Not Sensitive**.
    @ObservationIgnored var markNotSensitive: ((FlixItem.ID) -> Void)?

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// The "Moving…" toast on screen while a slow file command runs, so its end can take it away.
    @ObservationIgnored var progressToastID: FlixToast.ID?

    init(history: FlixHistory, intelligence: FlixIntelligence, settingsStore: FlixSettingsStore) {
        self.history = history
        self.intelligence = intelligence
        self.settingsStore = settingsStore
    }

    var settings: FlixSettings { settingsStore.settings }

    /// Whether a drag out keeps the panel open: the pin, or Settings' "Stay open".
    var staysOpenAfterDrag: Bool { isPinned || settings.afterDrag == .stayOpen }

    // MARK: The list

    /// The list as drawn. Cheap enough to rebuild per render: a filter pass over at most 5,000 items.
    var list: FlixListResult { FlixListBuilder.build(listInput) }

    /// What ``list`` is built from.
    var listInput: FlixListInput {
        FlixListInput(
            items: history.items, filter: filter, searchText: searchText, searchActive: searchActive,
            query: intelligence.query, moreLikeThis: intelligence.moreLikeThis, hidesNoise: settings.hidesNoise,
            showNoise: showNoise, annotations: intelligence.annotations, expandedVersions: expandedVersions,
            smartFilters: history.smartFilters, favorites: history.favorites, threads: intelligence.threads,
            now: now, semantic: { [intelligence] topic, item in intelligence.semanticMatch(topic: topic, item: item) })
    }

    /// The Fits card's rows, in its order, when it is ready.
    var fitItems: [(FlixFit, FlixItem)] {
        guard case .ready(let result) = intelligence.fits, isPlainList else { return [] }
        return result.fits.compactMap { fit in history.item(fit.itemID).map { (fit, $0) } }
    }

    /// The unfiltered first view, where the Fits, morning, and access cards appear.
    var isPlainList: Bool { filter == .all && !searchActive && intelligence.moreLikeThis == nil }

    /// Arrow-key order: the Fits rows first, then the list.
    var navigationOrder: [FlixItem.ID] {
        var seen = Set<FlixItem.ID>()
        return (fitItems.map(\.1.id) + list.order).filter { seen.insert($0).inserted }
    }

    var selectedItems: [FlixItem] {
        let order = navigationOrder
        return order.filter(selection.contains).compactMap(history.item)
    }

    /// The header title for the current view.
    var title: String {
        if searchActive { return String(localized: .flixTitleSearch) }
        if intelligence.moreLikeThis != nil { return String(localized: .flixTitleMoreLikeThis) }
        switch filter {
        case .activity(let activity): return String(localized: activity.title)
        case .kind(let kind): return String(localized: kind.title)
        case .thread(let id): return intelligence.thread(id)?.name ?? String(localized: .flixFilterAll)
        case .smart(let id): return history.smartFilters.first { $0.id == id }?.name ?? String(localized: .flixFilterAll)
        case .favorite(let id): return history.favorites.first { $0.id == id }?.name ?? String(localized: .flixFilterAll)
        }
    }

    // MARK: Lifecycle

    /// Resets for a fresh open. The newest row is selected, as the shortcut promises.
    func prepareForOpen(mode: FlixPanelMode, frontmost: FlixFrontmostContext?, policy: FlixReadPolicy) {
        self.mode = mode
        self.frontmost = frontmost
        readPolicy = policy
        now = .now
        filter = .all
        searchActive = false
        searchText = ""
        sheet = nil
        confirmation = nil
        toast = nil
        drag = nil
        isDropTargeted = false
        intelligence.clearMoreLikeThis()
        intelligence.clearQuery()
        pageOffer = nil
        foldersAwaitingAccess = settings.tracksWatchedFolders
            ? settings.enabledWatchedFolders.filter { $0.access == .unknown && policy.isProtected($0.path) } : []
        selection = []
        cursor = nil
        selectFirst()
        let workspace = NSWorkspace.shared
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
    }

    func panelDidClose() {
        searchTask?.cancel()
        toastTask?.cancel()
        settleTidy(undone: false)
        sheet = nil
        confirmation = nil
        drag = nil
    }

    // MARK: Selection

    func selectFirst() {
        guard let first = navigationOrder.first else { selection = []; cursor = nil; return }
        selection = [first]
        cursor = first
    }

    /// A press on a row. Command toggles, Shift extends from the cursor, a plain press on an already
    /// selected row keeps the selection so a drag can carry all of it.
    func press(_ id: FlixItem.ID, command: Bool, shift: Bool, origin: FlixActionOrigin = .list) {
        selectionOrigin = origin
        if command {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            cursor = id
        } else if shift, let cursor, let from = navigationOrder.firstIndex(of: cursor),
                  let to = navigationOrder.firstIndex(of: id) {
            selection = Set(navigationOrder[min(from, to)...max(from, to)])
        } else if !selection.contains(id) {
            selection = [id]
            cursor = id
        }
        quickLookSelectionChanged?(selectedItems.compactMap(\.shareURL))
    }

    /// A click that ended without a drag collapses a multiple selection to the clicked row.
    func click(_ id: FlixItem.ID, command: Bool, shift: Bool) {
        guard !command, !shift else { return }
        selection = [id]
        cursor = id
        quickLookSelectionChanged?(selectedItems.compactMap(\.shareURL))
    }

    func moveSelection(by distance: Int, extend: Bool) {
        let order = navigationOrder
        guard !order.isEmpty else { return }
        let current = cursor.flatMap(order.firstIndex) ?? (distance > 0 ? -1 : order.count)
        let next = min(max(0, current + distance), order.count - 1)
        let id = order[next]
        if extend { selection.insert(id) } else { selection = [id] }
        cursor = id
        // The Fits rows come first in arrow-key order and are not repeated below.
        selectionOrigin = fitItems.contains { $0.1.id == id } ? .fits : .list
        quickLookSelectionChanged?(selectedItems.compactMap(\.shareURL))
    }

    // MARK: Search

    func setSearchActive(_ active: Bool) {
        guard active != searchActive else { if active { searchFocusRequest += 1 }; return }
        searchActive = active
        if active {
            intelligence.clearMoreLikeThis()
            searchFocusRequest += 1
        } else {
            searchText = ""
            intelligence.clearQuery()
            selectFirst()
        }
    }

    /// Runs a suggested sentence at once.
    func runSearch(_ text: String) {
        setSearchActive(true)
        searchText = text
        searchTask?.cancel()
        intelligence.understand(text, items: history.items, now: now)
    }

    private func searchTextChanged() {
        searchTask?.cancel()
        guard intelligence.searchesInPlainWords else { selectFirst(); return }
        intelligence.clearQuery()
        let text = searchText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Typing pauses before a sentence is understood; each keystroke restarts the wait.
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, !Task.isCancelled else { return }
            intelligence.understand(text, items: history.items, now: now)
        }
    }

    private func filterChanged() {
        intelligence.clearMoreLikeThis()
        if searchActive { setSearchActive(false) }
        selectFirst()
    }

    // MARK: Toast

    /// Shows a toast in the footer for about four seconds, replacing any earlier one.
    func showToast(_ message: String, undo: (() -> Void)? = nil) {
        toastTask?.cancel()
        // A newer toast ends the Undo window of the one it replaces.
        settleTidy(undone: false)
        let toast = FlixToast(message: message, undo: undo)
        self.toast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.8))
            guard let self, !Task.isCancelled, self.toast?.id == toast.id else { return }
            self.toast = nil
            settleTidy(undone: false)
        }
    }

    func performUndo() {
        let undo = toast?.undo
        toast = nil
        settleTidy(undone: true)
        undo?()
    }
}

/// Where the open spring grows from, as a unit point in the content (0,0 top leading).
nonisolated struct FlixGrowthAnchor: Equatable, Sendable {
    var x: Double
    var y: Double
}
