import AppKit

/// The **Auto-Hide** and **Position** group that each dock tile's context menu shows above
/// **Settings…**.
///
/// One instance belongs to each panel's ``DockInteraction`` and is the target of the items it
/// builds. `NSMenuItem.target` is weak, so the owner has to outlive any menu that holds these
/// items; the interaction does.
///
/// The panel controller keeps ``autoHide``, ``alignment``, and ``edge`` in step with the
/// display's effective settings. The setters write where the display's value comes from, so a
/// change here matches the same change in Settings.
@MainActor
final class DockArrangementMenu: NSObject {
    /// This display's effective auto-hide preference.
    var autoHide = DockSettings.defaults.behavior.autoHide
    /// This display's effective along-edge alignment.
    var alignment = DockSettings.defaults.alignment
    /// This display's edge. Side docks name the choices Top, Center, and Bottom.
    var edge = DockSettings.defaults.edge
    var setAutoHide: ((Bool) -> Void)?
    var setAlignment: ((DockSettings.Alignment) -> Void)?

    /// Appends a separator and the group. Adds nothing when no setter is wired, as in previews.
    func addItems(to menu: NSMenu) {
        guard setAutoHide != nil, setAlignment != nil else { return }
        menu.addItem(.separator())

        let hide = NSMenuItem(title: String(localized: .dockMenuAutoHide), action: #selector(toggleAutoHide), keyEquivalent: "")
        hide.target = self
        hide.state = autoHide ? .on : .off
        hide.image = NSImage(systemSymbolName: "dock.arrow.down.rectangle", accessibilityDescription: nil)
        menu.addItem(hide)

        let position = NSMenuItem(title: String(localized: .dockMenuPosition), action: nil, keyEquivalent: "")
        position.image = NSImage(systemSymbolName: edge.isVertical ? "align.vertical.center" : "align.horizontal.center",
                                 accessibilityDescription: nil)
        let submenu = NSMenu()
        // The parent menus opt out of automatic enabling; a fresh submenu must too.
        submenu.autoenablesItems = false
        for option in DockSettings.Alignment.settingsOptions(edge: edge) {
            let entry = NSMenuItem(title: String(localized: option.title), action: #selector(chooseAlignment(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = option.value.rawValue
            entry.state = option.value == alignment ? .on : .off
            entry.image = NSImage(systemSymbolName: option.symbol, accessibilityDescription: nil)
            submenu.addItem(entry)
        }
        position.submenu = submenu
        menu.addItem(position)
    }

    // Both writes reconfigure the panel, so they wait until the menu has finished closing,
    // like the tile menus' other actions that move or reshape the dock.
    @objc private func toggleAutoHide() {
        let enabled = !autoHide, set = setAutoHide
        DispatchQueue.main.async { Analytics.performing(.menu) { set?(enabled) } }
    }

    @objc private func chooseAlignment(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = DockSettings.Alignment(rawValue: raw),
              value != alignment else { return }
        let set = setAlignment
        DispatchQueue.main.async { Analytics.performing(.menu) { set?(value) } }
    }
}
