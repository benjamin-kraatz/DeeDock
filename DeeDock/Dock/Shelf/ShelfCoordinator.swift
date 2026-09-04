import AppKit

/// App-wide owner for the single transient Shelf panel.
///
/// The Shelf itself is shared, so the panel can be opened from any display and always shows the
/// same items. Only one is open at a time, arbitrated with folder stacks by `DockPopoverPresenter`.
@MainActor
final class ShelfCoordinator {
    private let presenter: DockPopoverPresenter
    private let shelf: ShelfController
    private let organizer: any SemanticStackOrganizing
    private var controller: DockPopoverPanelController<ShelfPanelView>?
    private var state: ShelfPanelState?
    private let thumbnails = ShelfThumbnailLoader()
    private var displayID: String?
    private weak var sourcePanel: DockPanelController?
    var keyboardDismissed: ((String) -> Void)?
    var isOpen: Bool { controller != nil }

    init(shelf: ShelfController, presenter: DockPopoverPresenter,
         organizer: any SemanticStackOrganizing) {
        self.shelf = shelf
        self.presenter = presenter
        self.organizer = organizer
        presenter.register(.shelf) { [weak self] in self?.close(returnFocus: false) }
    }

    func toggle(on panel: DockPanelController, keyboard: Bool) {
        if displayID == panel.store.displayID, controller != nil {
            close(returnFocus: keyboard)
            return
        }
        close(returnFocus: false)
        presenter.prepareToOpen(.shelf)
        guard let anchor = panel.popoverAnchor(for: .shelf) else {
            panel.store.errorMessage = .shelfUnavailable
            return
        }

        let state = ShelfPanelState(organizer: organizer)
        state.apply(shelf.ordered, sort: shelf.sort, presentation: shelf.presentation,
                    animated: false) { [shelf] in shelf.resolve($0.id) }
        if let failure = shelf.loadFailure {
            state.report(failure) { [weak self] in self?.reloadFromStorage() }
        }
        let next = DockPopoverPanelController(anchor: anchor, keyboard: keyboard,
                                              ideal: CGSize(width: 420, height: 380)) { chrome in
            state.chrome = chrome
        } content: {
            ShelfPanelView(state: state, keyboard: keyboard)
        }
        self.state = state
        controller = next
        displayID = panel.store.displayID
        sourcePanel = panel
        panel.holdPopover(true)
        presenter.didOpen(.shelf)

        // Every edit reaches the panel again through the controller's own change notification.
        state.removeItems = { [weak panel] ids in panel?.store.removeFromShelf(ids: ids) }
        state.clearAll = { [weak self, weak panel] in
            guard let panel, self?.confirmClear() == true else { return }
            panel.store.clearShelf()
        }
        state.openItems = { [weak self] items in self?.open(items) }
        state.revealItems = { [weak self] items in self?.reveal(items) }
        state.copyItems = { [weak self] items in self?.copy(items) }
        state.sortChanged = { [weak self] value in
            guard let self else { return }
            do { try shelf.setSort(value) } catch { report(error) }
            reload(animated: true)
        }
        state.presentationChanged = { [weak self] value in
            guard let self else { return }
            do { try shelf.setPresentation(value) } catch { report(error) }
            reload(animated: false)
        }
        state.reloadSemantic = { [weak self] in self?.reload(animated: false) }
        state.requestThumbnail = { [weak self, weak panel] item, size in
            guard let self else { return }
            thumbnails.load(item, size: size, scale: panel?.backingScaleFactor ?? 2,
                            access: { [weak self] in self?.shelf.resolve(item.id) }) { [weak self] image in
                self?.state?.setThumbnail(image, for: item.id)
            }
        }
        // Taking an item out copies its reference. Removal stays explicit, so the item remains.
        state.beginDrag = { [weak self] items, view, event in
            self?.beginDrag(items: items, from: view, event: event)
        }
        next.willClose = { [weak self, weak state] in
            self?.thumbnails.stop()
            state?.stop()
        }
        next.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        next.closed = { [weak self, weak panel] returnFocus in
            let sourceID = panel?.store.displayID
            panel?.holdPopover(false)
            self?.presenter.didClose(.shelf)
            self?.controller = nil; self?.state = nil; self?.displayID = nil; self?.sourcePanel = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { self?.keyboardDismissed?(sourceID) }
        }
        next.show()
    }

    /// Begins a native file drag out of the Shelf tile itself, carrying every staged reference.
    func beginTileDrag(from view: NSView, event: NSEvent, on panel: DockPanelController) {
        beginDrag(items: shelf.items, from: view, event: event, panel: panel)
    }

    /// Re-reads storage after a load failure, then refreshes the panel.
    private func reloadFromStorage() {
        shelf.start()
        reload()
        if let failure = shelf.loadFailure {
            state?.report(failure) { [weak self] in self?.reloadFromStorage() }
        }
    }

    /// Reflects an edit made anywhere, including from another display's dock.
    func reload(animated: Bool = true) {
        guard let state else { return }
        state.apply(shelf.ordered, sort: shelf.sort, presentation: shelf.presentation,
                    animated: animated) { [shelf] in shelf.resolve($0.id) }
        thumbnails.retain(Set(state.order))
        if state.isEmpty, shelf.isEmpty, shelf.loadFailure == nil { state.error = nil }
    }

    func reanchor() {
        guard let controller, let sourcePanel, let anchor = sourcePanel.popoverAnchor(for: .shelf) else {
            close(returnFocus: false)
            return
        }
        controller.update(anchor)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || self.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(returnFocus: false); thumbnails.stop(); keyboardDismissed = nil }

    // MARK: - Item commands

    /// Opens each item with its default application, exactly as double-clicking it in Finder does.
    private func open(_ items: [ShelfItem]) {
        let resolved = items.compactMap { shelf.resolve($0.id) }
        guard !resolved.isEmpty else {
            state?.report(String(localized: .shelfUnavailableItems)) { [weak self] in self?.reload() }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        for access in resolved {
            NSWorkspace.shared.open(access.url, configuration: configuration) { [weak self] _, error in
                MainActor.assumeIsolated {
                    // The scope must outlive the asynchronous open, whatever its outcome.
                    defer { withExtendedLifetime(access) {} }
                    guard let error else { return }
                    self?.state?.report(error.localizedDescription) { [weak self] in self?.reload() }
                }
            }
        }
        // Everything that still exists was handed to macOS; anything missing is reported instead.
        guard resolved.count == items.count else {
            state?.report(String(localized: .shelfUnavailableItems)) { [weak self] in self?.reload() }
            return
        }
        close(returnFocus: false)
    }

    private func reveal(_ items: [ShelfItem]) {
        let resolved = items.compactMap { shelf.resolve($0.id) }
        guard !resolved.isEmpty else {
            state?.report(String(localized: .shelfUnavailableItems)) { [weak self] in self?.reload() }
            return
        }
        defer { withExtendedLifetime(resolved) {} }
        NSWorkspace.shared.activateFileViewerSelecting(resolved.map(\.url))
        close(returnFocus: false)
    }

    /// Writes file references, so pasting in Finder copies the files themselves.
    private func copy(_ items: [ShelfItem]) {
        let resolved = items.compactMap { shelf.resolve($0.id) }
        guard !resolved.isEmpty else {
            state?.report(String(localized: .shelfUnavailableItems)) { [weak self] in self?.reload() }
            return
        }
        defer { withExtendedLifetime(resolved) {} }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(resolved.map { $0.url as NSURL })
    }

    private func report(_ error: any Error) {
        state?.report(String(localized: .errorSaveShelf(details: error.localizedDescription))) { [weak self] in
            self?.reload()
        }
    }

    // MARK: - Private

    private func beginDrag(items: [ShelfItem], from view: NSView, event: NSEvent,
                           panel: DockPanelController? = nil) {
        let resolved = items.compactMap { item -> (ShelfResourceAccess, ShelfItem)? in
            guard let access = shelf.resolve(item.id) else { return nil }
            return (access, item)
        }
        let icons = resolved.map { access, _ -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: access.url.path)
            icon.size = NSSize(width: DockDragGeometry.imageSize, height: DockDragGeometry.imageSize)
            return icon
        }
        let started = ShelfDragSession.begin(accesses: resolved.map(\.0), ids: resolved.map(\.1.id),
                                             icons: icons, from: view, event: event) { [weak self] _ in
            // A completed drag never removes the item; only the panel needs to settle.
            self?.reload()
        }
        guard !started else { return }
        if let state { state.report(String(localized: .shelfUnavailableItems)) { [weak self] in self?.reload() } }
        else { (panel ?? sourcePanel)?.store.errorMessage = .shelfUnavailableItems }
    }

    private func confirmClear() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: .shelfClearConfirmationTitle)
        alert.informativeText = String(localized: .shelfClearConfirmationMessage)
        let clear = alert.addButton(withTitle: String(localized: .shelfClearConfirm))
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .shelfClearCancel))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a": state.selectAll(); return true
            case "r": state.revealSelection(); return true
            case "c": state.copyItems?(state.selectedItems); return true
            default: return false
            }
        }
        switch event.keyCode {
        case 53:
            // Escape drops a multiple selection first, then closes the panel.
            if state.selection.count > 1 { state.clearSelection() } else { close(returnFocus: true) }
        case 36, 76:
            state.openSelection()
        case 51, 117:
            state.removeSelection()
        case 125:
            state.select(by: 1)
        case 126:
            state.select(by: -1)
        default:
            return false
        }
        return true
    }
}
