import AppKit
import Observation

/// One display's pins and transient selection/error state; workspace work belongs to the shared catalog.
@MainActor @Observable
final class DockStore {
    let displayID: String
    /// Ordered render snapshots: this display's pins, followed by shared running applications.
    private(set) var items: [DockItem] = []
    /// A localized failure belonging only to this panel session.
    var errorMessage: LocalizedStringResource? { didSet { errorDidChange?() } }
    @ObservationIgnored var errorDidChange: (() -> Void)?
    /// Stable application identity, retained across changes to item ordering.
    var selectedID: String?
    /// Enabled by Focus Dock only; hover never enables keyboard handling.
    var keyboardFocus = false
    var launching: Set<String> { catalog.launching }
    @ObservationIgnored private let catalog: ApplicationCatalog
    var pinDestinations: [DockPinDestination] = []
    @ObservationIgnored var copyPin: ((ApplicationReference, String) -> Void)?
    var pins: [ApplicationReference] { profiles.pinLists[displayID] ?? [] }
    var canEditPins: Bool { !profiles.requiresReset && profiles.pinErrors[displayID] == nil }

    @ObservationIgnored private let profiles: DisplayProfilesStore
    @ObservationIgnored private var session = DockSession()
    @ObservationIgnored var applicationOpened: (() -> Void)?

    init(displayID: String, catalog: ApplicationCatalog, profiles: DisplayProfilesStore) {
        self.displayID = displayID
        self.catalog = catalog
        self.profiles = profiles
        errorMessage = profiles.pinErrors[displayID]
        refresh()
    }

    /// Rebuilds presentation from shared data without starting workspace observation.
    func refresh() {
        let pins = profiles.pinLists[displayID] ?? []
        let running = Dictionary(uniqueKeysWithValues: catalog.running.map { ($0.id, $0) })
        let favorites = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
        items = DockOrdering.itemOrder(favorites: pins, runningIDs: catalog.runningIDs).compactMap { id in
            guard let reference = favorites[id] ?? running[id] else { return nil }
            let access = ApplicationResourceAccess(reference)
            defer { withExtendedLifetime(access) {} }
            let url = catalog.service.resolvedURL(for: reference)
            return DockItem(reference: reference, icon: catalog.service.icon(for: url), isFavorite: favorites[id] != nil,
                            isRunning: running[id] != nil, isAvailable: url != nil)
        }
        if let selectedID, !items.contains(where: { $0.id == selectedID }) { self.selectedID = items.first?.id }
    }

    /// Saves this display's pins; the coordinator refreshes panels only after the write succeeds.
    func toggleFavorite(_ item: DockItem) {
        var pins = profiles.pinLists[displayID] ?? []
        if pins.contains(where: { $0.id == item.id }) { pins.removeAll { $0.id == item.id } }
        else { pins.append(item.reference) }
        do { try profiles.savePins(pins, for: displayID) }
        catch { errorMessage = .errorSavePins(details: error.localizedDescription) }
    }

    /// Persists one completed edit. Preview state must never call this method.
    @discardableResult
    func savePins(_ proposed: [ApplicationReference]) -> Bool {
        guard proposed != pins else { return true }
        do { try profiles.savePins(proposed, for: displayID); return true }
        catch { errorMessage = .errorSavePins(details: error.localizedDescription); return false }
    }

    func insertPins(_ references: [ApplicationReference], at index: Int) -> Bool {
        savePins(DockPinEditing.inserting(references, into: pins, at: index))
    }

    func movePin(_ id: String, by distance: Int) {
        _ = savePins(DockPinEditing.moving(id, in: pins, by: distance))
    }

    func canMovePin(_ id: String, by distance: Int) -> Bool {
        guard canEditPins, let index = pins.firstIndex(where: { $0.id == id }) else { return false }
        return pins.indices.contains(index + distance)
    }

    func removePin(_ id: String) -> Bool { savePins(pins.filter { $0.id != id }) }

    /// Submits to shared launch suppression and refuses completions after this panel is stopped.
    func open(_ item: DockItem) {
        let token = session.token
        catalog.open(item.reference) { [weak self] error in
            guard let self, session.accepts(token) else { return }
            if let error { errorMessage = error }
            else { applicationOpened?() }
        }
    }
    func moveSelection(by distance: Int) {
        guard !items.isEmpty else { return }
        let index = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        selectedID = items[(index + distance + items.count) % items.count].id
    }
    func openSelection() { if let item = items.first(where: { $0.id == selectedID }) { open(item) } }

    /// Ends this panel session without cancelling shared launches or removing global observers.
    func stop() { copyPin = nil; session.stop(); applicationOpened = nil; errorDidChange = nil; keyboardFocus = false; selectedID = nil }
}
