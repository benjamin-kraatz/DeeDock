import AppKit
import Observation
import SwiftUI

/// One presentation's search, selection, and cancellable intelligence, sharing discovery and history across displays.
@MainActor @Observable
final class LauncherState {
    let catalog: ApplicationCatalog
    var library: LauncherLibrary { catalog.launcherLibrary }
    var history: LauncherHistory { catalog.launcherHistory }
    var isPresented = false
    var contentVisible = false
    /// Drives the morph: false draws the panel at the dock's rect, true at the expanded rect.
    var expanded = false
    /// The expanded panel, in the presentation window's coordinates. The content lays out here for
    /// the whole morph and never moves, so nothing has to chase a changing layout.
    var contentRect = CGRect.zero
    /// The dock's own rect, in the same coordinates. The morph starts from this shape.
    var dockRect = CGRect.zero
    /// The morph's progress, 0 at the dock's rect and 1 at the expanded one. Both sets of contents
    /// fade against this rather than on timers of their own, so they move with the glass.
    var morph = 0.0
    /// Shifts the dock's contents from its own window's origin to the presentation window's, so
    /// they keep the position they had while they fade.
    var dockContentOffset = CGSize.zero
    let search = LauncherSearchState()
    /// Whether the launcher shows mixed search results instead of application-only results.
    /// Returns `false` while Robi suggestions are active.
    var usesMixedResults: Bool { robiIDs == nil && (!query.isEmpty || (search.kind != .all && search.kind != .application)) }
    var usesGridNavigation: Bool { !usesMixedResults && layout == .grid }
    var query = "" { didSet {
        guard oldValue != query else { return }
        cancelRobi(); search.invalidateQuery(); selectedID = nil; keyboardNavigationActive = false
    } }
    var filter: LauncherFilter = .all {
        didSet {
            selectedID = nil
            if filter == .recent { sort = .recent }
        }
    }
    var sort: LauncherSort = .name
    var grouping: LauncherGrouping = .none
    var layout: LauncherLayout = .grid
    var selectedID: String?
    var navigationColumns = 1
    var keyboardNavigationActive = false
    private var initialPinnedIDs: Set<String> = []
    var pinnedIDs: Set<String> { dockStore.map { Set($0.pins.compactMap { $0.application?.id }) } ?? initialPinnedIDs }
    var pinDestinations: [DockPinDestination] { dockStore?.pinDestinations ?? [] }
    @ObservationIgnored weak var dockStore: DockStore?
    @ObservationIgnored var createCapsule: ((ApplicationReference) -> Void)?
    var error: LocalizedStringResource?
    private(set) var robiIDs: [String]?
    private(set) var robiBusy = false
    var robiMessage: LocalizedStringResource?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var didOpen: (() -> Void)?
    @ObservationIgnored private let owner = UUID()
    @ObservationIgnored private let robi = LauncherRobi()
    @ObservationIgnored private var robiTask: Task<Void, Never>?
    @ObservationIgnored private var robiGeneration = UUID()
    @ObservationIgnored private var presentationGeneration = UUID()
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let iconProvider: ((LauncherApplication) -> NSImage)?

    init(catalog: ApplicationCatalog, iconProvider: ((LauncherApplication) -> NSImage)? = nil) {
        self.catalog = catalog
        self.iconProvider = iconProvider
    }

    var results: [LauncherApplication] {
        let query = LauncherApplication.normalize(query)
        let running = Set(catalog.runningIDs)
        let suggestions = robiIDs.map(Set.init)
        let matches: [(LauncherApplication, Int)] = library.applications.compactMap { app in
            switch filter {
            case .all: break
            case .running: guard running.contains(app.id) else { return nil }
            case .pinned: guard pinnedIDs.contains(app.id) else { return nil }
            case .recent: guard history.visits[app.id] != nil else { return nil }
            }
            if let suggestions { return suggestions.contains(app.id) ? (app, 0) : nil }
            return app.score(query).map { (app, $0) }
        }
        return matches.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let a = history.visits[lhs.0.id], b = history.visits[rhs.0.id]
            if sort == .frequent, (a?.count ?? 0) != (b?.count ?? 0) { return (a?.count ?? 0) > (b?.count ?? 0) }
            if sort == .recent {
                let ad = a?.lastOpened ?? .distantPast, bd = b?.lastOpened ?? .distantPast
                if ad != bd { return ad > bd }
            }
            let order = lhs.0.reference.name.localizedStandardCompare(rhs.0.reference.name)
            return order == .orderedSame ? lhs.0.id < rhs.0.id : order == .orderedAscending
        }.map(\.0)
    }

    struct Group: Identifiable {
        let id: String
        let applications: [LauncherApplication]
    }

    var groups: [Group] {
        let results = results
        if grouping == .none { return [Group(id: "", applications: results)] }
        let groups = Dictionary(grouping: results) { app in
            grouping == .category ? String(localized: LauncherCategory.title(app.category))
                : String(app.reference.name.prefix(1)).uppercased()
        }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { Group(id: $0, applications: groups[$0] ?? []) }
    }

    func begin(pins: [ApplicationReference]) {
        presentationGeneration = UUID()
        search.begin()
        initialPinnedIDs = Set(pins.map(\.id))
        query = ""; error = nil; selectedID = nil
        library.acquire(owner, extraURLs: pins.map(\.url) + catalog.running.map(\.url) + history.visits.values.map { $0.reference.url })
    }

    func end() {
        presentationGeneration = UUID()
        search.stop()
        cancelRobi(); library.release(owner); icons = [:]
        close = nil; didOpen = nil; error = nil
    }

    func icon(for application: LauncherApplication) -> NSImage {
        if let icon = icons[application.id] { return icon }
        let icon = iconProvider?(application) ?? NSWorkspace.shared.icon(forFile: application.reference.url.path)
        icon.size = NSSize(width: 96, height: 96)
        icons[application.id] = icon
        return icon
    }

    func open(_ application: LauncherApplication) {
        error = nil
        let token = presentationGeneration
        catalog.open(application.reference) { [weak self] error in
            guard let self, isPresented, presentationGeneration == token else { return }
            if let error { self.error = error }
            else { didOpen?() }
        }
    }

    func togglePin(_ application: LauncherApplication) {
        guard let dockStore else { return }
        let succeeded = pinnedIDs.contains(application.id)
            ? dockStore.removePin(application.id)
            : dockStore.insertPins([.application(application.reference)], at: dockStore.pins.count)
        if !succeeded { error = dockStore.errorMessage }
    }

    func showInFinder(_ application: LauncherApplication) {
        didOpen?()
        NSWorkspace.shared.activateFileViewerSelecting([application.reference.url])
    }

    func openSelection() {
        if usesMixedResults { search.openSelection(); return }
        let apps = groups.flatMap(\.applications)
        if let app = apps.first(where: { $0.id == selectedID }) ?? apps.first { open(app) }
    }

    func moveSelection(by distance: Int) {
        keyboardNavigationActive = true
        if usesMixedResults { search.moveSelection(by: distance); return }
        let apps = groups.flatMap(\.applications)
        guard !apps.isEmpty else { selectedID = nil; return }
        let current = selectedID.flatMap { id in apps.firstIndex { $0.id == id } }
        let index = current.map { min(max($0 + distance, 0), apps.count - 1) } ?? 0
        selectedID = apps[index].id
    }

    func askRobi() {
        cancelRobi()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let token = UUID(); robiGeneration = token
        let task = query, apps = library.applications, robi = robi
        robiBusy = true
        robiTask = Task { [weak self] in
            do {
                let ids = try await robi.suggestions(task: task, applications: apps)
                guard !Task.isCancelled, let self, robiGeneration == token else { return }
                robiIDs = ids; robiBusy = false; robiTask = nil
                robiMessage = ids.isEmpty ? .launcherRobiNoResults : .launcherRobiSuggestions
            } catch {
                guard !Task.isCancelled, let self, robiGeneration == token else { return }
                robiBusy = false; robiTask = nil
                robiMessage = error is LauncherRobi.Failure ? .launcherRobiUnavailable : .launcherRobiFailed
            }
        }
    }

    func cancelRobi() {
        robiGeneration = UUID(); robiTask?.cancel(); robiTask = nil
        robiBusy = false; robiIDs = nil; robiMessage = nil
    }
}
