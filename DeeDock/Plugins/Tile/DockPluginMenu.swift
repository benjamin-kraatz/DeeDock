import AppKit

/// The commands a plugin tile offers, shared by its right-click menu and the panel's More button.
///
/// Open or Close Panel, Open <app>, Restart Plugin, the plugin's own items, Unpin from Dock, and
/// Plugin Settings…. Restart is enabled only while the plugin is stopped.
struct DockPluginMenuActions {
    var togglePanel: () -> Void
    var openApp: () -> Void
    var restart: () -> Void
    var chooseItem: (String) -> Void
    var unpin: () -> Void
    var openSettings: () -> Void
}

/// Builds the plugin tile menu as an `NSMenu`, so the dock stays revealed while it tracks.
@MainActor
enum DockPluginMenu {
    /// - Parameters:
    ///   - panelOpen: Titles the first item Close Panel instead of Open Panel.
    ///   - target: Receives the item actions. The caller keeps it alive while the menu tracks.
    static func make(for plugin: DockPlugin, panelOpen: Bool, target: DockPluginMenuTarget) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: plugin.title))
        menu.addItem(target.item(panelOpen ? .pluginMenuClosePanel : .pluginMenuOpenPanel, symbol: "macwindow") {
            $0.togglePanel()
        })
        let openApp = target.item(.pluginMenuOpenApp(plugin.app.name), symbol: "arrow.up.forward.app") { $0.openApp() }
        openApp.isEnabled = plugin.app.url != nil
        menu.addItem(openApp)
        let restart = target.item(.pluginMenuRestart, symbol: "arrow.clockwise") { $0.restart() }
        restart.isEnabled = plugin.isStopped
        menu.addItem(restart)
        let items = plugin.menuItems
        if !items.isEmpty && !plugin.isStopped {
            menu.addItem(.separator())
            for entry in items {
                // Titles come from the plugin, already localized there.
                let item = target.item(verbatim: entry.title, symbol: entry.systemImage) { actions in
                    // Opening first sends panelOpened ahead of the choice, so the plugin can show
                    // the item's content in a panel it already knows is on screen.
                    if entry.opensPanel == true, !panelOpen { actions.togglePanel() }
                    actions.chooseItem(entry.id)
                }
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(target.item(.pluginMenuUnpin, symbol: "pin.slash") { $0.unpin() })
        menu.addItem(target.item(.pluginMenuSettings, symbol: "gear") { $0.openSettings() })
        return menu
    }
}

/// Holds a menu's actions and runs them with the menu trigger, so analytics see `menu`.
@MainActor
final class DockPluginMenuTarget: NSObject {
    var actions: DockPluginMenuActions?
    private var handlers: [Int: (DockPluginMenuActions) -> Void] = [:]

    func item(_ title: LocalizedStringResource, symbol: String?,
              action: @escaping (DockPluginMenuActions) -> Void) -> NSMenuItem {
        item(verbatim: String(localized: title), symbol: symbol, action: action)
    }

    func item(verbatim title: String, symbol: String?, action: @escaping (DockPluginMenuActions) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self
        item.tag = handlers.count
        handlers[item.tag] = action
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return item
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let actions, let handler = handlers[sender.tag] else { return }
        Analytics.performing(.menu) { handler(actions) }
    }

    func reset() {
        handlers.removeAll()
        actions = nil
    }
}
