import AppKit
import SwiftUI

struct FolderContextMenuBridge: NSViewRepresentable {
    let item: FolderDockItem
    let interaction: DockInteraction
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.item = item; view.interaction = interaction; view.openSettings = openSettings; view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        var item: FolderDockItem?
        weak var interaction: DockInteraction?
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
            let menu = NSMenu(); menu.delegate = self
            add(.folderStackOpen, action: #selector(openStack), symbol: "square.grid.2x2", to: menu, enabled: item.isAvailable)
            add(.folderStackShowInFinder, action: #selector(showInFinder), symbol: "finder", to: menu, enabled: item.isAvailable)
            add(.folderItemAddToShelf, action: #selector(stageOnShelf), symbol: "tray.and.arrow.down", to: menu,
                enabled: item.isAvailable && interaction?.stageFolderOnShelf != nil)
            menu.addItem(.separator())
            add(.folderStackGrid, action: #selector(useGrid), symbol: "square.grid.2x2", to: menu,
                state: item.reference.presentation == .grid ? .on : .off)
            add(.folderStackList, action: #selector(useList), symbol: "list.bullet", to: menu,
                state: item.reference.presentation == .list ? .on : .off)
            menu.addItem(.separator())
            let vertical = interaction?.layout.edge.isVertical == true
            add(vertical ? .actionMoveUp : .actionMoveLeft, action: #selector(movePrevious), symbol: vertical ? "arrow.up" : "arrow.left", to: menu,
                enabled: (item.isDownloads ? interaction?.canMoveUtility : interaction?.canMovePin)?(item.id, -1) == true)
            add(vertical ? .actionMoveDown : .actionMoveRight, action: #selector(moveNext), symbol: vertical ? "arrow.down" : "arrow.right", to: menu,
                enabled: (item.isDownloads ? interaction?.canMoveUtility : interaction?.canMovePin)?(item.id, 1) == true)
            if !item.isDownloads, let destinations = interaction?.pinDestinations, !destinations.isEmpty {
                let parent = NSMenuItem(title: String(localized: .actionPinOnDisplay), action: nil, keyEquivalent: "")
                parent.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
                let submenu = NSMenu()
                for destination in destinations {
                    let child = NSMenuItem(title: destination.name, action: #selector(copyToDisplay(_:)), keyEquivalent: "")
                    child.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
                    child.target = self; child.representedObject = destination.id; submenu.addItem(child)
                }
                parent.submenu = submenu; menu.addItem(parent)
            }
            if !item.isDownloads { add(.actionUnpin, action: #selector(unpin), symbol: "pin.slash", to: menu) }
            menu.addItem(.separator())
            add(.actionSettings, action: #selector(settings), symbol: "gear", to: menu)
            menu.autoenablesItems = false
            trackedMenu = menu
            menu.popUp(besideDockTile: self, edge: interaction?.layout.edge, event: event)
            tracking?(false); trackedMenu = nil
        }

        private func add(_ title: LocalizedStringResource, action: Selector, symbol: String? = nil,
                         to menu: NSMenu, enabled: Bool = true, state: NSControl.StateValue = .off) {
            let entry = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
            entry.target = self; entry.isEnabled = enabled; entry.state = state
            if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func openStack() { if let item { Analytics.performing(.menu) { interaction?.openFolder?(item, false) } } }
        @objc private func stageOnShelf() { if let item { Analytics.performing(.menu) { interaction?.stageFolderOnShelf?(item) } } }
        @objc private func showInFinder() { if let item { interaction?.revealFolder?(item) } }
        @objc private func useGrid() { if let item { interaction?.setFolderPresentation?(item.reference.id, .grid) } }
        @objc private func useList() { if let item { interaction?.setFolderPresentation?(item.reference.id, .list) } }
        @objc private func movePrevious() {
            if let item { Analytics.performing(.menu) { (item.isDownloads ? interaction?.moveUtility : interaction?.movePin)?(item.id, -1) } }
        }
        @objc private func moveNext() {
            if let item { Analytics.performing(.menu) { (item.isDownloads ? interaction?.moveUtility : interaction?.movePin)?(item.id, 1) } }
        }
        @objc private func unpin() { if let item { Analytics.performing(.menu) { interaction?.removePin?(item.id) } } }
        @objc private func copyToDisplay(_ sender: NSMenuItem) {
            if let item, let id = sender.representedObject as? String { interaction?.copyPin?(.folder(item.reference), id) }
        }
        @objc private func settings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking(); trackedMenu?.delegate = nil; trackedMenu = nil
            tracking?(false); tracking = nil; interaction = nil; openSettings = nil; item = nil
        }
    }
}
