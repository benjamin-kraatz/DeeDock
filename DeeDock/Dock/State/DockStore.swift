import AppKit
import Observation

/// Owns dock data, persisted pins, and bounded launch requests on the main actor.
/// Call `start()` from app lifecycle code and `stop()` before releasing the store.
@MainActor @Observable
final class DockStore {
    /// Ordered render snapshots: pinned applications followed by running-only applications.
    private(set) var items: [DockItem] = []
    /// Identities with an outstanding launch request; drives progress indicators.
    private(set) var launching: Set<String> = []
    /// A deferred localized failure, cleared by the error-banner dismiss action.
    var errorMessage: LocalizedStringResource?
    /// Current keyboard selection, kept stable across item reordering.
    var selectedID: String?
    /// Enabled only by an explicit Focus Dock action, never by pointer entry.
    var keyboardFocus = false

    @ObservationIgnored private let service: ApplicationService
    @ObservationIgnored private let repository: FavoritesRepository
    @ObservationIgnored private var favorites: [ApplicationReference] = []
    @ObservationIgnored private var runningIDs: [String] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var launchTasks: [String: Task<Void, Never>] = [:]
    /// Informs the panel owner after a complete snapshot change so it can update geometry.
    @ObservationIgnored var itemsDidChange: (() -> Void)?
    /// Notifies the panel owner after a successful launch so explicit keyboard focus can end.
    @ObservationIgnored var applicationOpened: (() -> Void)?

    /// Injects workspace and persistence dependencies without starting observation or reading pins.
    init(service: ApplicationService, repository: FavoritesRepository) {
        self.service = service
        self.repository = repository
    }

    /// Creates the production dependencies; lifecycle work remains deferred until `start()`.
    convenience init() {
        self.init(service: ApplicationService(), repository: FavoritesRepository())
    }

    /// Loads saved pins and installs workspace observers once, then publishes the first snapshot.
    func start() {
        guard observers.isEmpty else { return }
        do { favorites = try repository.load { service.defaultFavorites() } }
        catch { errorMessage = .errorLoadPins(details: error.localizedDescription) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    /// Reconciles the workspace snapshot while retaining existing running-app order and selection.
    func refresh() {
        let running = DockOrdering.unique(service.runningApplications())
        runningIDs = DockOrdering.runningOrder(previous: runningIDs, current: running)
        let runningByID = Dictionary(uniqueKeysWithValues: running.map { ($0.id, $0) })
        let favoritesByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        let orderedIDs = DockOrdering.itemOrder(favorites: favorites, runningIDs: runningIDs)
        items = orderedIDs.compactMap { id in
            guard let reference = runningByID[id] ?? favoritesByID[id] else { return nil }
            let url = service.resolvedURL(for: reference)
            return DockItem(reference: reference, icon: service.icon(for: url), isFavorite: favoritesByID[id] != nil,
                            isRunning: runningByID[id] != nil, isAvailable: url != nil)
        }
        service.pruneIcons(keeping: Set(items.compactMap { service.resolvedURL(for: $0.reference) }))
        if let selectedID, !items.contains(where: { $0.id == selectedID }) { self.selectedID = items.first?.id }
        itemsDidChange?()
    }

    /// Pins or unpins an item, committing the new ordering only after persistence succeeds.
    func toggleFavorite(_ item: DockItem) {
        var updated = favorites
        if item.isFavorite { updated.removeAll { $0.id == item.id } }
        else { updated.append(item.reference) }
        do {
            // Keep the visible ordering unchanged if encoding the new pins fails.
            try repository.save(updated)
            favorites = updated
            refresh()
        } catch { errorMessage = .errorSavePins(details: error.localizedDescription) }
    }

    /// Requests a launch once per identity and exposes failures as localized UI state.
    func open(_ item: DockItem) {
        guard launchTasks[item.id] == nil else { return }
        launching.insert(item.id)
        launchTasks[item.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                launching.remove(item.id)
                launchTasks[item.id] = nil
            }
            do {
                try await service.open(item.reference)
                // A system launch can outlive cancellation; do not publish into a stopped dock.
                guard !Task.isCancelled else { return }
                applicationOpened?()
                refresh()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = .errorOpenApp(appName: item.reference.name, details: error.localizedDescription)
            }
        }
    }

    /// Moves keyboard selection by one neighboring step, wrapping at either end.
    func moveSelection(by distance: Int) {
        guard !items.isEmpty else { return }
        let index = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        selectedID = items[(index + distance + items.count) % items.count].id
    }

    /// Opens the selected item if it still exists in the current snapshot.
    func openSelection() {
        if let item = items.first(where: { $0.id == selectedID }) { open(item) }
    }

    /// Removes workspace observers, cancels owned tasks, and releases panel callbacks.
    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        launchTasks.values.forEach { $0.cancel() }
        launchTasks.removeAll()
        launching.removeAll()
        itemsDidChange = nil
        applicationOpened = nil
    }
}
