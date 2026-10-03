import AppKit

/// App-wide owner for the single transient folder stack.
@MainActor
final class FolderStackCoordinator {
    private let presenter: DockPopoverPresenter
    private let organizer: any SemanticStackOrganizing
    private var controller: FolderStackPanelController?
    private var displayID: String?
    private var folderID: UUID?
    /// The tile the open stack points at. A folder's own tile unless the caller named another,
    /// such as a volume showing its root.
    private var anchorTarget: DockEntryID?
    private var folderURL: URL?
    private var springOpened = false
    private var springCleanup: Task<Void, Never>?
    private weak var sourcePanel: DockPanelController?
    var keyboardDismissed: ((String) -> Void)?
    var isOpen: Bool { controller != nil }
    var isKeyboardActive: Bool { controller != nil && sourcePanel?.store.keyboardFocus == true }

    init(presenter: DockPopoverPresenter, organizer: any SemanticStackOrganizing) {
        self.presenter = presenter
        self.organizer = organizer
        presenter.register(.folderStack) { [weak self] in self?.close(returnFocus: false) }
    }

    /// - Parameter target: The tile to attach to. Defaults to the folder's own tile.
    func show(_ folder: FolderDockItem, on panel: DockPanelController, keyboard: Bool, spring: Bool = false,
              anchoredTo target: DockEntryID? = nil) {
        let target = target ?? .folder(folder.reference.id)
        guard !QuarantineStore.shared.contains(folder.id, url: folder.reference.url),
              !QuarantineStore.shared.unreadable else {
            panel.store.errorMessage = .quarantineBlocked
            return
        }
        springCleanup?.cancel()
        if folderID == folder.reference.id, displayID == panel.store.displayID {
            if spring { return }
            close(returnFocus: keyboard)
            return
        }
        close(returnFocus: false)
        presenter.prepareToOpen(.folderStack)
        guard folder.isAvailable, let anchor = panel.popoverAnchor(for: target) else {
            panel.store.errorMessage = .folderStackUnavailable
            return
        }

        var reference = folder.reference
        let access = FolderResourceAccess(reference)
        if access.isAvailable, access.bookmarkIsStale,
           let bookmark = try? access.url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil) {
            reference.bookmarkData = bookmark
            if !panel.store.refreshFolderReference(reference) { return }
        }

        let sortKey = "folderStackSort.\(panel.store.displayID).\(reference.id.uuidString)"
        let sort = UserDefaults.standard.string(forKey: sortKey).flatMap(FolderStackSort.init(rawValue:))
            ?? (folder.isDownloads ? .recency : .alphabetical)
        let next = FolderStackPanelController(folder: reference, anchor: anchor, keyboard: keyboard,
                                              organizer: organizer, sort: sort)
        next.state.sortChanged = { UserDefaults.standard.set($0.rawValue, forKey: sortKey) }
        displayID = panel.store.displayID
        folderID = reference.id
        anchorTarget = target
        folderURL = reference.url.standardizedFileURL
        sourcePanel = panel
        controller = next
        springOpened = spring
        next.state.copyFailed = { [weak panel] message in panel?.store.errorMessage = .folderDropError(message) }
        panel.holdPopover(true)
        presenter.didOpen(.folderStack)
        next.state.stageOnShelf = { [weak next, weak panel] entry in
            guard let next, let panel, let lease = next.state.dragLease() else { return }
            // Keep the parent scope alive until the Shelf has saved the child's bookmark.
            let access = DocumentResourceAccess([entry.url], retaining: [lease])
            if !panel.store.stageOnShelf(access), let message = panel.store.errorMessage {
                next.state.report(String(localized: message)) { [weak next] in
                    next?.state.stageOnShelf?(entry)
                }
            }
        }
        next.state.openEntry = { [weak next] in next?.open($0) }
        next.state.presentationChanged = { [weak panel] in panel?.store.setFolderPresentation($0, for: reference.id) == true }
        next.state.dragCompleted = { [weak next] accepted in
            if accepted, next?.state.copying != true { next?.close(returnFocus: false) }
        }
        next.closed = { [weak self, weak panel] returnFocus in
            let sourceID = panel?.store.displayID
            panel?.holdPopover(false)
            self?.presenter.didClose(.folderStack)
            self?.controller = nil; self?.displayID = nil; self?.folderID = nil
            self?.anchorTarget = nil; self?.folderURL = nil; self?.sourcePanel = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { self?.keyboardDismissed?(sourceID) }
        }
        next.show()
    }

    func receive(_ info: NSDraggingInfo, folder: FolderDockItem, on panel: DockPanelController) -> Bool {
        show(folder, on: panel, keyboard: false, spring: true)
        return controller?.state.receive(info, into: controller?.state.rootURL) ?? false
    }

    /// A spring-opened stack survives a successful copy so progress and failures stay visible.
    func dragEnded() {
        guard springOpened, let current = controller else { return }
        springCleanup?.cancel()
        // Native destination callbacks may end before another destination commits its drop.
        springCleanup = Task { [weak self, weak current] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, let current, controller === current,
                  !current.state.copying, !current.state.receivedDrop else { return }
            close(returnFocus: false)
        }
    }

    func reanchor() {
        guard let controller, let sourcePanel, let anchorTarget,
              let anchor = sourcePanel.popoverAnchor(for: anchorTarget) else {
            close(returnFocus: false)
            return
        }
        controller.update(anchor)
    }

    /// Closes the stack when it shows `url` or anything inside it. Its directory watcher holds the
    /// folder open, which would make an unmount of that volume fail.
    func close(within url: URL) {
        let root = url.standardizedFileURL.path
        guard let folderURL else { return }
        let path = folderURL.path
        guard path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return }
        close(returnFocus: false)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || self.displayID == displayID else { return }
        springCleanup?.cancel(); springCleanup = nil
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(returnFocus: false); keyboardDismissed = nil }
}
