import Foundation

/// App-wide owner for the one Focus Dock mode picker.
@MainActor
final class DockModePickerCoordinator {
    private var controller: DockModePickerPanelController?
    private weak var sourcePanel: DockPanelController?
    var isKeyboardActive: Bool { controller != nil && sourcePanel?.store.keyboardFocus == true }

    func show(modes: [DockMode], activeModeID: UUID, on panel: DockPanelController,
              choose: @escaping (UUID) -> Bool) {
        close(returnFocus: false)
        guard let anchor = panel.modePickerAnchor() else { return }
        let next = DockModePickerPanelController(modes: modes, activeModeID: activeModeID, anchor: anchor)
        sourcePanel = panel
        controller = next
        panel.holdModePicker(true)
        next.state.choose = { [weak self, weak panel] id in
            guard let self, let panel else { return }
            close(returnFocus: false)
            _ = choose(id)
            panel.focus()
        }
        next.closed = { [weak self, weak panel] returnFocus in
            panel?.holdModePicker(false)
            self?.controller = nil
            self?.sourcePanel = nil
            if returnFocus { panel?.focus() }
        }
        next.show()
    }

    func close(returnFocus: Bool) { controller?.close(returnFocus: returnFocus) }
    func stop() { close(returnFocus: false) }
}
