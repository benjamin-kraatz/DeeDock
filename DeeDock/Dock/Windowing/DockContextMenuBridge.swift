import AppKit
import SwiftUI

/// Native menu ownership gives each dock a reliable tracking hold without observing unrelated menus.
struct DockContextMenuBridge: NSViewRepresentable {
    let item: DockItem
    let open: () -> Void
    let togglePin: () -> Void
    var interaction: DockInteraction? = nil
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.item = item
        view.open = open
        view.togglePin = togglePin
        view.interaction = interaction
        view.openSettings = openSettings
        view.tracking = tracking
    }

    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    /// Only context-clicks reach this overlay; ordinary left-clicks remain SwiftUI button actions.
    final class MenuView: NSView, NSMenuDelegate {
        var item: DockItem?
        weak var interaction: DockInteraction?
        var open: (() -> Void)?
        var togglePin: (() -> Void)?
        var openSettings: (() -> Void)?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func isAccessibilityElement() -> Bool { false }

        override func rightMouseDown(with event: NSEvent) { show(event) }

        override func mouseDown(with event: NSEvent) { show(event) }

        private func show(_ event: NSEvent) {
            guard let item else { return }

            let menu = NSMenu()
            menu.delegate = self

            if item.isAvailable {
                let entry = NSMenuItem(title: String(localized: .actionOpen), action: #selector(openApplication), keyEquivalent: "")
                entry.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
                entry.target = self
                menu.addItem(entry)
                let files = NSMenuItem(title: String(localized: .actionOpenFiles), action: #selector(openFiles), keyEquivalent: "o")
                files.keyEquivalentModifierMask = .command
                files.target = self
                files.isEnabled = interaction?.openFiles != nil
                menu.addItem(files)
                menu.addItem(.separator())
            }

            let pin = NSMenuItem(title: String(localized: item.isFavorite ? .actionUnpin : .actionPin), action: #selector(changePin), keyEquivalent: "")
            pin.image = NSImage(systemSymbolName: item.isFavorite ? "pin.slash" : "pin", accessibilityDescription: nil)
            pin.target = self
            menu.addItem(pin)

            if item.isFavorite {
                for (title, action, distance) in [(String(localized: interaction?.layout.edge.isVertical == true ? .actionMoveUp : .actionMoveLeft), #selector(movePinLeft), -1),
                                                  (String(localized: interaction?.layout.edge.isVertical == true ? .actionMoveDown : .actionMoveRight), #selector(movePinRight), 1)] {
                    let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    entry.target = self
                    entry.isEnabled = interaction?.canMovePin?(item.id, distance) == true
                    menu.addItem(entry)
                }
            }
            if let destinations = interaction?.pinDestinations, !destinations.isEmpty {
                let parent = NSMenuItem(title: String(localized: .actionPinOnDisplay), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for destination in destinations {
                    let entry = NSMenuItem(title: destination.name, action: #selector(copyPinToDisplay(_:)), keyEquivalent: "")
                    entry.target = self; entry.representedObject = destination.id
                    submenu.addItem(entry)
                }
                parent.submenu = submenu; menu.addItem(parent)
            }
            menu.autoenablesItems = false

            menu.addItem(.separator())

            let settings = NSMenuItem(title: String(localized: .actionSettings), action: #selector(showSettings), keyEquivalent: "")
            settings.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
            settings.target = self
            menu.addItem(settings)

            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            // Menu callbacks normally close the hold; this is also safe if tracking was cancelled.
            tracking?(false)
            trackedMenu = nil
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }

        func menuDidClose(_ menu: NSMenu) { tracking?(false) }

        @objc private func openApplication() { open?() }

        @objc private func openFiles() {
            guard let item, item.isAvailable else { return }
            // Let menu tracking release its hold before the native picker gains focus.
            let action = interaction?.openFiles
            DispatchQueue.main.async { action?(item) }
        }

        @objc private func changePin() { togglePin?() }

        @objc private func movePinLeft() { if let item { interaction?.movePin?(item.id, -1) } }
        @objc private func movePinRight() { if let item { interaction?.movePin?(item.id, 1) } }
        @objc private func copyPinToDisplay(_ sender: NSMenuItem) {
            if let item, let id = sender.representedObject as? String { interaction?.copyPin?(item.reference, id) }
        }

        @objc private func showSettings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            open = nil
            togglePin = nil
            openSettings = nil
        }
    }
}
