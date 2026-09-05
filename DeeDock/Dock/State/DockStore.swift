import AppKit
import Observation
import UniformTypeIdentifiers

/// One display's pins and transient selection/error state; workspace work belongs to the shared catalog.
@MainActor @Observable
final class DockStore {
    let focusSession: FocusSessionController?
    @ObservationIgnored var openFocusSession: (() -> Void)?
    let actions: ActionTilesController?
    let displayID: String
    /// Filters running-only apps and Finder, including its pin. Other pins and section visibility remain independent.
    var visibleApplicationIDs: Set<String>?
    private var windowSnapshots: [DockWindowSnapshot] = []
    private var windowGroupsEnabled = false
    private var keepWindowGroupsExpanded = false
    private var expandedWindowApps: Set<String> = []
    @ObservationIgnored private let windowSelection = DockWindowSelection()
    /// Ordered render snapshots: this display's pins, followed by shared running applications.
    private(set) var items: [DockItem] = []
    private(set) var folders: [FolderDockItem] = []
    /// A localized failure belonging only to this panel session.
    var errorMessage: LocalizedStringResource? { didSet { errorDidChange?() } }
    @ObservationIgnored var errorDidChange: (() -> Void)?
    /// Stable application or control identity, retained across changes to entry ordering.
    var selectedTarget: DockEntryID?
    /// Compatibility for app-only callers; controls have no application identity.
    var selectedID: String? {
        get { if case .app(let id) = selectedTarget { return id }; return nil }
        set { selectedTarget = newValue.map(DockEntryID.app) }
    }
    let sections = DockSectionState()
    private(set) var entries: [DockRenderSlot] = []
    @ObservationIgnored var presentationDidChange: (() -> Void)?
    /// Enabled by Focus Dock only; hover never enables keyboard handling.
    var keyboardFocus = false
    var launching: Set<String> { catalog.busyApplications }
    @ObservationIgnored private let catalog: ApplicationCatalog
    var pinDestinations: [DockPinDestination] = []
    @ObservationIgnored var copyPin: ((DockPin, String) -> Void)?
    @ObservationIgnored var openFolder: ((FolderDockItem, Bool) -> Void)?
    @ObservationIgnored var openShelf: (() -> Void)?
    @ObservationIgnored var openSessionCapsules: (() -> Void)?
    @ObservationIgnored var openSessionCapsule: ((UUID) -> Void)?
    var pins: [DockPin] { profiles.pinLists[displayID] ?? [] }
    var canEditPins: Bool {
        !profiles.requiresReset && !profiles.modes.requiresReset && profiles.pinErrors[displayID] == nil
    }

    @ObservationIgnored private let profiles: DisplayProfilesStore
    @ObservationIgnored private let trash: TrashController?
    @ObservationIgnored private let shelf: ShelfController?
    @ObservationIgnored private let capsules: SessionCapsuleController?
    @ObservationIgnored private var showsTrash = true
    @ObservationIgnored private var showsShelf = true
    @ObservationIgnored private var showsSessionCapsules = true
    @ObservationIgnored private var session = DockSession()
    @ObservationIgnored var applicationOpened: (() -> Void)?

    init(displayID: String, catalog: ApplicationCatalog, profiles: DisplayProfilesStore,
         trash: TrashController? = nil, shelf: ShelfController? = nil,
         capsules: SessionCapsuleController? = nil, actions: ActionTilesController? = nil, focusSession: FocusSessionController? = nil) {
        self.focusSession = focusSession
        self.actions = actions
        self.displayID = displayID
        self.catalog = catalog
        self.profiles = profiles
        self.trash = trash
        self.shelf = shelf
        self.capsules = capsules
        errorMessage = profiles.pinErrors[displayID]
        sections.didChange = { [weak self] in self?.refreshEntries(); self?.presentationDidChange?() }
        refresh()
    }

    /// Rebuilds presentation from shared data without starting workspace observation.
    func refresh() {
        let pins = profiles.pinLists[displayID] ?? []
        let pinnedApplications = pins.compactMap(\.application)
        let running = Dictionary(uniqueKeysWithValues: catalog.running.map { ($0.id, $0) })
        let favorites = Dictionary(uniqueKeysWithValues: pinnedApplications.map { ($0.id, $0) })
        let runningIDs = catalog.runningIDs.filter { visibleApplicationIDs?.contains($0) ?? true }
        items = DockOrdering.itemOrder(favorites: pinnedApplications, runningIDs: runningIDs).compactMap { id in
            // Finder stays running for the desktop. On filtered secondary docks its saved
            // pin appears only with an actual visible window; persistence is untouched.
            if id == "com.apple.finder", let visibleApplicationIDs,
               !visibleApplicationIDs.contains(id) { return nil }
            guard let reference = favorites[id] ?? running[id] else { return nil }
            let access = ApplicationResourceAccess(reference)
            defer { withExtendedLifetime(access) {} }
            let url = catalog.service.resolvedURL(for: reference)
            return DockItem(reference: reference, icon: catalog.service.icon(for: url), isFavorite: favorites[id] != nil,
                            isRunning: running[id] != nil, isAvailable: url != nil)
        }
        folders = pins.compactMap { pin -> FolderDockItem? in
            guard let reference = pin.folder else { return nil }
            let access = FolderResourceAccess(reference)
            defer { withExtendedLifetime(access) {} }
            let available = access.isAvailable
            let icon: NSImage
            if available {
                icon = catalog.service.icon(for: access.url)
            } else {
                icon = NSWorkspace.shared.icon(for: .folder)
                icon.size = NSSize(width: 128, height: 128)
            }
            return FolderDockItem(reference: reference, icon: icon, isAvailable: available)
        }
        refreshEntries()
    }

    private func refreshEntries() {
        let base = DockSectionProjection.entries(items: items, folders: folders, pins: pins,
                                                  visibility: sections.visibility, expanded: sections.isExpanded,
                                                  actions: actions?.dockItems ?? [], focus: focusSession?.item,
                                                  sessionCapsules: showsSessionCapsules ? capsules?.dockItems ?? [] : [],
                                                  capsules: showsSessionCapsules ? capsules?.item : nil,
                                                  shelf: showsShelf ? shelf?.item : nil,
                                                  trash: showsTrash ? trash?.item : nil)
        let next = DockWindowProjection.entries(base, windows: windowSnapshots, enabled: windowGroupsEnabled,
            keepExpanded: keepWindowGroupsExpanded, expandedApps: expandedWindowApps)
        selectedTarget = DockSectionProjection.repairedSelection(selectedTarget, previous: entries, current: next)
        entries = next
    }

    /// The coordinator supplies only windows assigned to this display.
    func configureWindowGroups(_ windows: [DockWindowSnapshot], enabled: Bool, expanded: Bool) {
        if !enabled || expanded != keepWindowGroupsExpanded { expandedWindowApps.removeAll() }
        if !enabled { windowSelection.stop() }
        windowSnapshots = windows
        windowGroupsEnabled = enabled
        keepWindowGroupsExpanded = expanded
        expandedWindowApps.formIntersection(Set(windows.map(\.applicationID)))
    }

    func toggleWindowGroup(_ applicationID: String) {
        guard windowGroupsEnabled, !keepWindowGroupsExpanded else { return }
        if !expandedWindowApps.insert(applicationID).inserted { expandedWindowApps.remove(applicationID) }
        refreshEntries()
        presentationDidChange?()
    }

    func selectWindow(_ item: DockWindowItem) {
        guard windowGroupsEnabled, windowSnapshots.contains(where: { $0.id == item.window.id }) else { return }
        windowSelection.select(item.window) { [weak self] succeeded in
            guard let self else { return }
            if succeeded { applicationOpened?() }
            else { errorMessage = .windowGroupsSelectionFailed }
        }
    }

    /// Sleep and session resignation cancel an in-flight request before it can raise a window.
    func cancelWindowSelection() { windowSelection.stop() }

    func configureTrash(_ visible: Bool) {
        guard showsTrash != visible else { return }
        showsTrash = visible
        refreshEntries()
    }

    func configureShelf(_ visible: Bool) {
        guard showsShelf != visible else { return }
        showsShelf = visible
        refreshEntries()
    }

    func configureSessionCapsules(_ visible: Bool) {
        guard showsSessionCapsules != visible else { return }
        showsSessionCapsules = visible
        refreshEntries()
    }

    // MARK: - Shelf

    /// Stages a user-supplied Finder batch. The files themselves are never moved or copied.
    func stageOnShelf(_ access: DocumentResourceAccess) {
        guard let shelf else {
            errorMessage = .shelfUnavailable
            return
        }
        do {
            let rejected = try shelf.add(access.urls)
            if rejected > 0 { errorMessage = .shelfFull(limit: ShelfDocument.capacity) }
        } catch {
            errorMessage = .errorSaveShelf(details: error.localizedDescription)
        }
    }

    func removeFromShelf(ids: Set<UUID>) {
        guard let shelf else {
            errorMessage = .shelfUnavailable
            return
        }
        do { try shelf.remove(ids: ids) } catch { errorMessage = .errorSaveShelf(details: error.localizedDescription) }
    }

    func clearShelf() {
        guard let shelf else {
            errorMessage = .shelfUnavailable
            return
        }
        do { try shelf.clear() } catch { errorMessage = .errorSaveShelf(details: error.localizedDescription) }
    }

    func openTrash() {
        let token = session.token
        guard let trash else {
            errorMessage = .trashUnavailable
            return
        }
        trash.open { [weak self] errorDescription in
            guard let self, session.accepts(token), let errorDescription else { return }
            errorMessage = .trashAutomationActionFailed(details: errorDescription)
        }
    }

    func emptyTrash() {
        let token = session.token
        guard let trash else {
            errorMessage = .trashUnavailable
            return
        }
        trash.empty { [weak self] errorDescription in
            guard let self, session.accepts(token), let errorDescription else { return }
            errorMessage = .trashAutomationActionFailed(details: errorDescription)
        }
    }

    func recycleToTrash(_ access: DocumentResourceAccess) {
        let token = session.token
        guard let trash else {
            errorMessage = .trashUnavailable
            return
        }
        trash.recycle(access) { [weak self] error in
            guard let self, session.accepts(token), let error else { return }
            errorMessage = .trashMoveFailed(details: error.localizedDescription)
        }
    }

    /// Saves this display's pins; the coordinator refreshes panels only after the write succeeds.
    func toggleFavorite(_ item: DockItem) {
        var pins = profiles.pinLists[displayID] ?? []
        if pins.contains(where: { $0.application?.id == item.id }) { pins.removeAll { $0.application?.id == item.id } }
        else { pins.append(.application(item.reference)) }
        do { try profiles.savePins(pins, for: displayID) }
        catch { errorMessage = .errorSavePins(details: error.localizedDescription) }
    }

    /// Persists one completed edit. Preview state must never call this method.
    @discardableResult
    func savePins(_ proposed: [DockPin]) -> Bool {
        guard proposed != pins else { return true }
        do { try profiles.savePins(proposed, for: displayID); return true }
        catch { errorMessage = .errorSavePins(details: error.localizedDescription); return false }
    }

    func insertPins(_ incoming: [DockPin], at index: Int) -> Bool {
        savePins(DockPinEditing.inserting(incoming, into: pins, at: index))
    }

    func movePin(_ id: String, by distance: Int) {
        _ = savePins(DockPinEditing.moving(id, in: pins, by: distance))
    }

    func canMovePin(_ id: String, by distance: Int) -> Bool {
        guard canEditPins, let index = pins.firstIndex(where: { $0.id == id }) else { return false }
        return pins.indices.contains(index + distance)
    }

    func removePin(_ id: String) -> Bool { savePins(pins.filter { $0.id != id }) }

    func setFolderPresentation(_ presentation: FolderStackPresentation, for id: UUID) -> Bool {
        var proposed = pins
        guard let index = proposed.firstIndex(where: { $0.folder?.id == id }),
              var folder = proposed[index].folder else { return false }
        folder.presentation = presentation
        proposed[index] = .folder(folder)
        return savePins(proposed)
    }

    func refreshFolderReference(_ folder: FolderReference) -> Bool {
        var proposed = pins
        guard let index = proposed.firstIndex(where: { $0.folder?.id == folder.id }) else { return false }
        proposed[index] = .folder(folder)
        return savePins(proposed)
    }

    /// Submits to shared launch suppression and refuses completions after this panel is stopped.
    func performPrimaryAction(_ item: DockItem) {
        let token = session.token
        catalog.performPrimaryAction(item.reference) { [weak self] error in
            guard let self, session.accepts(token) else { return }
            if let error { errorMessage = error }
            else { applicationOpened?() }
        }
    }

    /// Opens or activates an app without applying the app-icon hide toggle.
    func open(_ item: DockItem) {
        let token = session.token
        catalog.open(item.reference) { [weak self] error in
            guard let self, session.accepts(token) else { return }
            if let error { errorMessage = error }
            else { applicationOpened?() }
        }
    }

    /// Captures this panel's session, not its mutable selection or display index.
    func openDocuments(_ documents: DocumentResourceAccess, with reference: ApplicationReference) {
        let token = session.token
        catalog.openDocuments(documents, with: reference) { [weak self] error in
            guard let self, session.accepts(token) else { return }
            if let error { errorMessage = error }
            else { applicationOpened?() }
        }
    }

    /// A spring activation may outlive hover, but late failures must not reveal an abandoned target.
    func springOpen(_ item: DockItem, isCurrent: @escaping () -> Bool) {
        let token = session.token
        catalog.springOpen(item.reference, isCurrent: { [weak self] in
            self?.session.accepts(token) == true && isCurrent()
        }) { [weak self] error in
            guard let self, session.accepts(token), isCurrent() else { return }
            if let error { errorMessage = error }
        }
    }
    func moveSelection(by distance: Int) {
        guard !entries.isEmpty else { return }
        let index = selectedTarget.flatMap { id in entries.firstIndex { $0.target == id } } ?? 0
        selectedTarget = entries[(index + distance + entries.count) % entries.count].target
    }
    func openSelection() {
        guard let entry = entries.first(where: { $0.target == selectedTarget }) else { return }
        switch entry {
        case .window(let item): selectWindow(item)
        case .windowGroup(let group): toggleWindowGroup(group.app.id)
        case .focus: openFocusSession?()
        case .action(let item): actions?.run(item.tile.id)
        case .app(let item): open(item)
        case .folder(let folder): openFolder?(folder, keyboardFocus)
        case .group: sections.toggle()
        case .sessionCapsule(let item): openSessionCapsule?(item.capsuleID)
        case .sessionCapsules: openSessionCapsules?()
        case .shelf: openShelf?()
        case .trash: openTrash()
        case .gap: break
        }
    }

    /// Ends this panel session without cancelling shared launches or removing global observers.
    func stop() { windowSelection.stop(); openFocusSession = nil; sections.stop(); presentationDidChange = nil; copyPin = nil; openFolder = nil; openShelf = nil; openSessionCapsules = nil; openSessionCapsule = nil; session.stop(); applicationOpened = nil; errorDidChange = nil; keyboardFocus = false; selectedID = nil }
}
