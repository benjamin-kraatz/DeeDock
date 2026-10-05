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

    /// - Parameters:
    ///   - target: The tile to attach to. Defaults to the folder's own tile.
    ///   - volumeRoot: Shows a mounted volume. Its stack moves drops with Shift and lets a drag
    ///     climb back out through the back button; folder stacks keep plain copying.
    func show(_ folder: FolderDockItem, on panel: DockPanelController, keyboard: Bool, spring: Bool = false,
              anchoredTo target: DockEntryID? = nil, volumeRoot: Bool = false) {
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

        let reference = folder.reference
        let sortKey = "folderStackSort.\(panel.store.displayID).\(reference.id.uuidString)"
        let sort = UserDefaults.standard.string(forKey: sortKey).flatMap(FolderStackSort.init(rawValue:))
            ?? (folder.isDownloads ? .recency : .alphabetical)
        let next = FolderStackPanelController(folder: reference, anchor: anchor, keyboard: keyboard,
                                              organizer: organizer, sort: sort)
        next.state.bookmarkRefresh = { [weak panel] bookmark in
            var updated = reference
            updated.bookmarkData = bookmark
            return panel?.store.refreshFolderReference(updated) == true
        }
        next.state.sortChanged = { UserDefaults.standard.set($0.rawValue, forKey: sortKey) }
        next.state.allowsMoveDrops = volumeRoot
        next.state.springsUp = volumeRoot
        let kind: AnalyticsStackKind = volumeRoot ? .drive : folder.isDownloads ? .downloads : .folder
        next.state.analyticsKind = kind
        next.appeared = {
            if spring, Analytics.shared.ambientTrigger == nil { Analytics.count(.springLoad(kind)) }
            Analytics.track(.stackOpened(kind, presentation: reference.presentation, sort: sort,
                                         trigger: spring ? Analytics.shared.ambientTrigger ?? .springLoad
                                             : Analytics.trigger(keyboard: keyboard)))
        }
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

    func receive(_ info: NSDraggingInfo, folder: FolderDockItem, on panel: DockPanelController,
                 anchoredTo target: DockEntryID? = nil, volumeRoot: Bool = false) -> Bool {
        // A drop opens the stack the way spring loading does, but it is a drop, not a spring.
        Analytics.performing(.drag) {
            show(folder, on: panel, keyboard: false, spring: true, anchoredTo: target, volumeRoot: volumeRoot)
        }
        return controller?.state.receive(info, into: controller?.state.rootURL, target: .tile) ?? false
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
    /// folder open, which would make an unmount of that volume fail. The check is lexical so a
    /// share that is already going away cannot stall this call on the main thread.
    func close(within url: URL) {
        guard let folderURL, folderURL.isSameOrDescendant(of: url, resolvingSymlinks: false) else { return }
        close(returnFocus: false)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || self.displayID == displayID else { return }
        springCleanup?.cancel(); springCleanup = nil
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(returnFocus: false); keyboardDismissed = nil }
}
