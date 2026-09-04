import SwiftUI

/// The trailing system Trash tile. File operations remain owned by the shared controller.
struct DockTrashButton: View {
    let item: TrashDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openTrash?() } label: {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction.layout.edge,
                available: item.state != .unavailable, running: false, launching: false,
                keyboardSelected: selected, artworkOpacity: artworkOpacity,
                artworkAnimation: interaction.idleFade.animation)
                .overlay {
                    if interaction.trashTargeted {
                        DockDocumentHighlight(emphasized: false).allowsHitTesting(false)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.state == .unavailable)
        .overlay {
            TrashContextMenuBridge(item: item, interaction: interaction, openSettings: {
                interaction.prepareSettings?()
                NSApp.activate()
                openSettings()
            }, emptyTrash: confirmEmptyTrash, tracking: menuTracking)
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(.trashName))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(.trashOpenHint))
        .accessibilityAction(named: Text(.trashOpen)) { interaction.openTrash?() }
        .accessibilityAction(named: Text(.trashEmptyAction)) { confirmEmptyTrash() }
    }

    private func confirmEmptyTrash() {
        guard item.state == .full else { return }
        guard interaction.confirmsTrashEmpty else {
            interaction.emptyTrash?()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: .trashEmptyConfirmationTitle)
        alert.informativeText = String(localized: .trashEmptyConfirmationMessage)
        let emptyButton = alert.addButton(withTitle: String(localized: .trashEmptyConfirm))
        emptyButton.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .trashEmptyCancel))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { interaction.emptyTrash?() }
    }

    private var accessibilityValue: LocalizedStringResource {
        switch item.state {
        case .empty: .trashEmpty
        case .full: .trashFull
        case .unknown: .trashStatusUnknown
        case .unavailable: .trashUnavailable
        }
    }
}

private struct TrashContextMenuBridge: NSViewRepresentable {
    let item: TrashDockItem
    let interaction: DockInteraction
    let openSettings: () -> Void
    let emptyTrash: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.item = item
        view.interaction = interaction
        view.openSettings = openSettings
        view.emptyTrash = emptyTrash
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        var item: TrashDockItem?
        weak var interaction: DockInteraction?
        var openSettings: (() -> Void)?
        var emptyTrash: (() -> Void)?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func rightMouseDown(with event: NSEvent) { show(event) }
        override func mouseDown(with event: NSEvent) { show(event) }

        private func show(_ event: NSEvent) {
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            add(.trashOpen, action: #selector(openTrash), symbol: "trash", to: menu,
                enabled: item?.state != .unavailable)
            add(.trashEmptyAction, action: #selector(empty), symbol: "trash.slash", to: menu,
                enabled: item?.state == .full)
            menu.addItem(.separator())
            add(.actionSettings, action: #selector(settings), symbol: "gear", to: menu)
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        private func add(_ title: LocalizedStringResource, action: Selector, symbol: String,
                         to menu: NSMenu, enabled: Bool = true) {
            let entry = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func openTrash() { interaction?.openTrash?() }
        @objc private func empty() { emptyTrash?() }
        @objc private func settings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            openSettings = nil
            emptyTrash = nil
            item = nil
        }
    }
}
