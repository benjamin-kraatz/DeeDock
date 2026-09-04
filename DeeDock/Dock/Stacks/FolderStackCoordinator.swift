import Foundation

/// App-wide owner for the single transient folder stack.
@MainActor
final class FolderStackCoordinator {
    private let presenter: DockPopoverPresenter
    private let organizer: any SemanticStackOrganizing
    private var controller: FolderStackPanelController?
    private var displayID: String?
    private var folderID: UUID?
    private weak var sourcePanel: DockPanelController?
    var keyboardDismissed: ((String) -> Void)?
    var isOpen: Bool { controller != nil }
    var isKeyboardActive: Bool { controller != nil && sourcePanel?.store.keyboardFocus == true }

    init(presenter: DockPopoverPresenter, organizer: any SemanticStackOrganizing) {
        self.presenter = presenter
        self.organizer = organizer
        presenter.register(.folderStack) { [weak self] in self?.close(returnFocus: false) }
    }

    func show(_ folder: FolderDockItem, on panel: DockPanelController, keyboard: Bool) {
        if folderID == folder.reference.id, displayID == panel.store.displayID {
            close(returnFocus: keyboard)
            return
        }
        close(returnFocus: false)
        presenter.prepareToOpen(.folderStack)
        guard folder.isAvailable, let anchor = panel.popoverAnchor(for: .folder(folder.reference.id)) else {
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

        let next = FolderStackPanelController(folder: reference, anchor: anchor, keyboard: keyboard,
                                              organizer: organizer)
        displayID = panel.store.displayID
        folderID = reference.id
        sourcePanel = panel
        controller = next
        panel.holdPopover(true)
        presenter.didOpen(.folderStack)
        next.state.openEntry = { [weak next] in next?.open($0) }
        next.state.presentationChanged = { [weak panel] in panel?.store.setFolderPresentation($0, for: reference.id) == true }
        next.state.dragCompleted = { [weak next] accepted in if accepted { next?.close(returnFocus: false) } }
        next.closed = { [weak self, weak panel] returnFocus in
            let sourceID = panel?.store.displayID
            panel?.holdPopover(false)
            self?.presenter.didClose(.folderStack)
            self?.controller = nil; self?.displayID = nil; self?.folderID = nil; self?.sourcePanel = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { self?.keyboardDismissed?(sourceID) }
        }
        next.show()
    }

    func reanchor() {
        guard let controller, let sourcePanel, let folderID,
              let anchor = sourcePanel.popoverAnchor(for: .folder(folderID)) else {
            close(returnFocus: false)
            return
        }
        controller.update(anchor)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || self.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(returnFocus: false); keyboardDismissed = nil }
}
