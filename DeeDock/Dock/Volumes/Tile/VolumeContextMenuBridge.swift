import AppKit
import SwiftUI

/// Right-click menu for a volume tile: Open, Open in Hub, Eject, Hide from Dock, and the Drives
/// settings page.
struct VolumeContextMenuBridge: NSViewRepresentable {
    let item: VolumeDockItem
    let interaction: DockInteraction
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.item = item
        view.interaction = interaction
        view.openSettings = openSettings
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        var item: VolumeDockItem?
        weak var interaction: DockInteraction?
        var openSettings: (() -> Void)?
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
            let available = item?.isEjecting == false
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            add(.volumeOpen, action: #selector(open), symbol: "square.stack.3d.up", to: menu, enabled: available)
            add(.hubOpenInHub, action: #selector(openInHub), symbol: "macwindow", to: menu, enabled: available)
            menu.addItem(.separator())
            add(.volumeEject, action: #selector(eject), symbol: "eject", to: menu, enabled: available)
            menu.addItem(.separator())
            add(.volumeHideFromDock, action: #selector(hide), symbol: "eye.slash", to: menu)
            add(.volumeManageDrives, action: #selector(settings), symbol: "gear", to: menu)
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
        @objc private func open() { if let item { interaction?.openVolume?(item) } }
        @objc private func openInHub() { if let item { Analytics.performing(.menu) { interaction?.openVolumeInHub?(item) } } }
        @objc private func eject() { if let item { Analytics.performing(.menu) { interaction?.ejectVolume?(item) } } }
        @objc private func hide() { if let item { interaction?.hideVolume?(item) } }
        @objc private func settings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            openSettings = nil
            item = nil
        }
    }
}
