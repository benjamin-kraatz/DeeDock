import AppKit
import SwiftUI

/// Owns the native menu's whole tracking loop, including transitions into monitor submenus.
/// A stable snapshot prevents focus-driven SwiftUI updates from replacing an open menu.
struct AppMeltOverflowButton: NSViewRepresentable {
    let pair: AppMeltPair
    let controller: AppMeltController

    func makeCoordinator() -> Coordinator { Coordinator(pair: pair, controller: controller) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: String(localized: .meltPairActions))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        button.setAccessibilityLabel(String(localized: .meltPairActions))
        button.target = context.coordinator
        button.action = #selector(Coordinator.open(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = pair.canChangeLayout
        button.toolTip = String(localized: .meltPairActions)
    }

    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        coordinator.menu?.cancelTracking()
        button.target = nil
    }

    @MainActor final class Coordinator: NSObject {
        private let pair: AppMeltPair
        private weak var controller: AppMeltController?
        fileprivate var menu: NSMenu?
        private var actions: [() -> Void] = []
        private var selection: Int?

        init(pair: AppMeltPair, controller: AppMeltController) {
            self.pair = pair
            self.controller = controller
        }

        @objc func open(_ sender: NSButton) {
            guard let controller, pair.canChangeLayout, menu == nil else { return }
            let root = NSMenu()
            root.autoenablesItems = false
            actions = []; selection = nil
            add(pair.fittedFrom == nil ? .meltFit : .meltRestoreSize, to: root) { [pair] in controller.toggleFit(pair) }
            add(.meltUndoLayout, to: root, enabled: pair.undoLayout != nil) { [pair] in controller.undo(pair) }
            let displays = AppMeltGeometry.displays
            if displays.count > 1 {
                let item = NSMenuItem(title: String(localized: .meltMoveDisplay), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for display in displays {
                    addTitle(display.name, to: submenu) { [pair] in controller.move(pair, to: display.id) }
                }
                item.submenu = submenu
                root.addItem(item)
            }
            root.addItem(.separator())
            add(.meltSmaller, to: root) { [pair] in controller.resizeFromToolbar(pair, dx: 40, dy: 25) }
            add(.meltLarger, to: root) { [pair] in controller.resizeFromToolbar(pair, dx: -40, dy: -25) }
            root.addItem(.separator())
            add(.meltUnpair, to: root) { [pair] in controller.unpair(pair) }
            menu = root
            pair.isTrackingToolbarMenu = true
            // Do not release ownership when an individual submenu closes. popUp returns
            // only after the entire menu tree has finished tracking or has been cancelled.
            root.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY : sender.bounds.minY), in: sender)
            let action = selection.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
            menu = nil; actions = []; selection = nil
            pair.isTrackingToolbarMenu = false
            pair.chromeInteractionChanged?()
            // Execute after tracking ends, so layout changes cannot dismantle an active menu.
            guard controller.pairs.contains(where: { $0.id == pair.id }), pair.canChangeLayout else { return }
            action?()
        }

        private func add(_ title: LocalizedStringResource, to menu: NSMenu,
                         enabled: Bool = true, action: @escaping () -> Void) {
            addTitle(String(localized: title), to: menu, enabled: enabled, action: action)
        }

        private func addTitle(_ title: String, to menu: NSMenu,
                              enabled: Bool = true, action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            item.isEnabled = enabled
            actions.append(action)
            menu.addItem(item)
        }

        @objc private func selectItem(_ sender: NSMenuItem) { selection = sender.tag }
    }
}
