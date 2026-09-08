import AppKit

/// Native menu supplies keyboard navigation and VoiceOver without adding Peek shortcut collisions.
@MainActor final class WindowActionMenu: NSObject {
    private var selected: WindowAction?
    private var menu: NSMenu?

    func cancel() { menu?.cancelTracking() }

    func show(capabilities: WindowActionCapabilities, displays: [WindowActionDisplay],
              at point: CGPoint) -> WindowAction? {
        selected = nil
        let menu = NSMenu()
        menu.autoenablesItems = false
        self.menu = menu
        add(capabilities.minimized ? .peekActionRestore : .peekActionMinimize,
            action: .minimized(!capabilities.minimized), enabled: capabilities.canMinimize, to: menu)
        add(.peekActionClose, action: .close, enabled: capabilities.canClose, to: menu)
        let geometryMenu = NSMenu()
        geometryMenu.autoenablesItems = false
        let move = NSMenuItem(title: String(localized: .peekActionMove), action: nil, keyEquivalent: "")
        let destinations = NSMenu()
        destinations.autoenablesItems = false
        for display in displays {
            addTitle(display.name, action: .place(.move, displayID: display.id), enabled: capabilities.canMove, to: destinations)
        }
        move.submenu = destinations
        if capabilities.canMove && !displays.isEmpty { geometryMenu.addItem(move) }
        if let frame = capabilities.frame, let current = WindowPlacementPolicy.current(frame, displays: displays) {
            for placement in [WindowPlacement.left, .right, .center, .fill] {
                add(placement.label, action: .place(placement, displayID: current.id),
                    enabled: capabilities.canMove && (placement == .center || capabilities.canResize), to: geometryMenu)
            }
        }
        add(.peekActionUndo, action: .undo, enabled: capabilities.canUndo && capabilities.canMove, to: geometryMenu)
        if !geometryMenu.items.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for item in geometryMenu.items {
                geometryMenu.removeItem(item)
                menu.addItem(item)
            }
        }
        guard !menu.items.isEmpty else { self.menu = nil; return nil }
        menu.popUp(positioning: nil, at: point, in: nil)
        self.menu = nil
        return selected
    }

    private func add(_ label: LocalizedStringResource, action: WindowAction, enabled: Bool, to menu: NSMenu) {
        addTitle(String(localized: label), action: action, enabled: enabled, to: menu)
    }
    private func addTitle(_ title: String, action: WindowAction, enabled: Bool, to menu: NSMenu) {
        guard enabled else { return }
        let item = NSMenuItem(title: title, action: #selector(take(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(action)
        item.isEnabled = enabled
        menu.addItem(item)
    }
    @objc private func take(_ sender: NSMenuItem) { selected = (sender.representedObject as? ActionBox)?.action }
    private final class ActionBox {
        let action: WindowAction
        init(_ action: WindowAction) { self.action = action }
    }
}

private extension WindowPlacement {
    var label: LocalizedStringResource {
        switch self {
        case .move: .peekActionMove
        case .left: .peekActionLeft
        case .right: .peekActionRight
        case .center: .peekActionCenter
        case .fill: .peekActionFill
        }
    }
}
