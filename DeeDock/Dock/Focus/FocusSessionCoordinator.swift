import AppKit

/// Anchors the shared timer controls to the display where the user clicked its tile.
@MainActor
final class FocusSessionCoordinator {
    private let focus: FocusSessionController
    private let presenter: DockPopoverPresenter
    private var controller: DockPopoverPanelController<FocusSessionPanelView>?
    private weak var source: DockPanelController?
    var keyboardDismissed: ((String) -> Void)?
    var saveCapsule: ((DockPanelController) -> Void)?
    var isOpen: Bool { controller != nil }

    init(focus: FocusSessionController, presenter: DockPopoverPresenter) {
        self.focus = focus; self.presenter = presenter
        presenter.register(.focus) { [weak self] in self?.close() }
    }
    func toggle(on panel: DockPanelController) {
        if source === panel, controller != nil { close(); return }
        close()
        guard focus.session != nil, let anchor = panel.popoverAnchor(for: .focus) else { return }
        presenter.prepareToOpen(.focus)
        let keyboard = panel.store.keyboardFocus
        let chrome = FocusSessionPanelChrome()
        let next = DockPopoverPanelController(anchor: anchor, keyboard: true,
                                              ideal: CGSize(width: 400, height: 290),
                                              chromeChanged: { chrome.value = $0 }) {
            FocusSessionPanelView(controller: focus, chrome: chrome, saveCapsule: { [weak self, weak panel] in
                guard let self, let panel else { return }
                close()
                saveCapsule?(panel)
            }, close: { [weak self] in self?.close() })
        }
        controller = next; source = panel
        panel.holdPopover(true); presenter.didOpen(.focus)
        next.keyHandler = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            self?.close(returnFocus: panel.store.keyboardFocus)
            return true
        }
        next.closed = { [weak self, weak panel] returnsFocus in
            self?.controller = nil; self?.source = nil
            panel?.holdPopover(false); self?.presenter.didClose(.focus)
            if returnsFocus { panel?.focus() }
            else if keyboard, let id = panel?.store.displayID { self?.keyboardDismissed?(id) }
        }
        next.show()
    }
    func reanchor() {
        guard controller != nil else { return }
        guard focus.session != nil, let source, let anchor = source.popoverAnchor(for: .focus) else { close(); return }
        controller?.update(anchor)
    }
    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || source?.store.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }
    func stop() { close(); saveCapsule = nil; keyboardDismissed = nil }
}
