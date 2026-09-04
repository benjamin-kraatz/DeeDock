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
        private var snapshot: ApplicationMenuSnapshot?
        private var discoveryID: UUID?
        private var selectedWindowToken: ApplicationWindowToken?

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
            selectedWindowToken = nil
            snapshot = interaction?.applicationMenuSnapshot?(item)
                ?? ApplicationMenuSnapshot(processes: [], windowState: .hidden)

            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            rebuild(menu)
            trackedMenu = menu

            if let snapshot, snapshot.windowState == .loading {
                discoveryID = interaction?.beginApplicationWindowDiscovery?(item, snapshot) { [weak self, weak menu] state in
                    guard let self, let menu, trackedMenu === menu, let previous = self.snapshot else { return }
                    self.snapshot = ApplicationMenuSnapshot(processes: previous.processes, windowState: state)
                    self.rebuild(menu)
                }
            }

            NSMenu.popUpContextMenu(menu, with: event, for: self)
            finishTracking()
        }

        private func rebuild(_ menu: NSMenu) {
            guard let item, let snapshot else { return }
            let applicationActions = ApplicationContextMenuProjection.applicationActions(
                isAvailable: item.isAvailable,
                snapshot: snapshot
            )
            menu.removeAllItems()
            addWindows(snapshot.windowState, to: menu)

            if item.isAvailable {
                addItem(.actionOpen, symbol: "arrow.up.forward.app", action: #selector(openApplication), to: menu)
                let files = addItem(.actionOpenFiles, action: #selector(openFiles), to: menu)
                files.keyEquivalent = "o"
                files.keyEquivalentModifierMask = .command
                files.isEnabled = interaction?.openFiles != nil
                if applicationActions.contains(.showInFinder) {
                    addItem(.applicationMenuShowInFinder, symbol: "finder", action: #selector(showInFinder), to: menu)
                }
            }

            if snapshot.isRunning {
                menu.addItem(.separator())
                for action in applicationActions where action != .showInFinder {
                    switch action {
                    case .setHidden:
                        addItem(snapshot.allProcessesHidden ? .applicationMenuShow : .applicationMenuHide,
                                action: #selector(changeHiddenState), to: menu)
                    case .bringAllToFront:
                        addItem(.applicationMenuBringAllToFront, action: #selector(bringAllToFront), to: menu)
                    case .quit:
                        addItem(.applicationMenuQuit, action: #selector(quitApplication), to: menu)
                    case .showInFinder, .selectWindow:
                        break
                    }
                }
            }

            menu.addItem(.separator())
            addItem(item.isFavorite ? .actionUnpin : .actionPin,
                    symbol: item.isFavorite ? "pin.slash" : "pin",
                    action: #selector(changePin), to: menu)

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
                    entry.target = self
                    entry.representedObject = destination.id
                    submenu.addItem(entry)
                }
                parent.submenu = submenu
                menu.addItem(parent)
            }

            menu.addItem(.separator())
            addItem(.actionSettings, symbol: "gear", action: #selector(showSettings), to: menu)
        }

        private func addWindows(_ state: ApplicationWindowMenuState, to menu: NSMenu) {
            switch state {
            case .hidden:
                return
            case .loading:
                addDisabledItem(.applicationMenuWindowsLoading, to: menu)
            case .unavailable:
                addDisabledItem(.applicationMenuWindowsUnavailable, to: menu)
            case .loaded(let windows):
                guard !windows.isEmpty else {
                    addDisabledItem(.applicationMenuNoWindows, to: menu)
                    menu.addItem(.separator())
                    return
                }
                let titles = ApplicationContextMenuProjection.windowTitles(
                    windows,
                    untitled: String(localized: .applicationMenuUntitledWindow)
                )
                for (window, title) in zip(windows, titles) {
                    let entry = NSMenuItem(title: title, action: #selector(selectWindow(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = window.token
                    entry.state = window.isMain ? .on : .off
                    if window.isMinimized {
                        entry.image = NSImage(systemSymbolName: "minus.square", accessibilityDescription: String(localized: .applicationMenuMinimized))
                    }
                    menu.addItem(entry)
                }
            }
            menu.addItem(.separator())
        }

        @discardableResult
        private func addItem(_ title: LocalizedStringResource, symbol: String? = nil,
                             action: Selector, to menu: NSMenu) -> NSMenuItem {
            let entry = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
            entry.target = self
            if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(entry)
            return entry
        }

        private func addDisabledItem(_ title: LocalizedStringResource, to menu: NSMenu) {
            let entry = NSMenuItem(title: String(localized: title), action: nil, keyEquivalent: "")
            entry.isEnabled = false
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { finishTracking() }

        @objc private func openApplication() { open?() }

        @objc private func openFiles() {
            guard let item, item.isAvailable else { return }
            let action = interaction?.openFiles
            DispatchQueue.main.async { action?(item) }
        }

        @objc private func showInFinder() { perform(.showInFinder) }
        @objc private func changeHiddenState() { perform(.setHidden(!(snapshot?.allProcessesHidden ?? false))) }
        @objc private func bringAllToFront() { perform(.bringAllToFront) }
        @objc private func quitApplication() { perform(.quit) }

        @objc private func selectWindow(_ sender: NSMenuItem) {
            guard let token = sender.representedObject as? ApplicationWindowToken else { return }
            selectedWindowToken = token
            trackedMenu?.cancelTracking()
            finishTracking()
            perform(.selectWindow(token))
        }

        private func perform(_ action: ApplicationMenuAction) {
            guard let item else { return }
            let handler = interaction?.performApplicationMenuAction
            DispatchQueue.main.async { handler?(action, item) }
        }

        @objc private func changePin() { togglePin?() }
        @objc private func movePinLeft() { if let item { interaction?.movePin?(item.id, -1) } }
        @objc private func movePinRight() { if let item { interaction?.movePin?(item.id, 1) } }
        @objc private func copyPinToDisplay(_ sender: NSMenuItem) {
            if let item, let id = sender.representedObject as? String { interaction?.copyPin?(.application(item.reference), id) }
        }
        @objc private func showSettings() { openSettings?() }

        private func finishTracking() {
            if selectedWindowToken == nil, let discoveryID {
                interaction?.cancelApplicationWindowDiscovery?(discoveryID)
            }
            discoveryID = nil
            tracking?(false)
            trackedMenu = nil
            snapshot = nil
        }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            finishTracking()
            tracking = nil
            interaction = nil
            open = nil
            togglePin = nil
            openSettings = nil
        }
    }
}
