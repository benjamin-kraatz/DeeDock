import AppKit

/// Native context menus for Files items and pane backgrounds.
///
/// While a menu tracks, the Hub holds `.menu`, so an anchored Hub stays open even though menu
/// tracking takes key focus. Shortcut glyphs are shown for reference; the shortcuts themselves
/// are handled by `HubFilesModel.handleKeyDown`.
@MainActor
enum HubFilesContextMenu {
    /// The menu for the selected items (search results while searching).
    static func items(model: HubFilesModel) -> NSMenu {
        let menu = HubFilesMenu(model: model)
        let items = model.actionableItems
        let single = items.count == 1
        menu.add(.hubFilesMenuOpen, key: "\r", modifiers: []) { model.openSelection() }
        menu.add(.hubFilesMenuQuickLook, key: " ", modifiers: []) { model.toggleQuickLook() }
        menu.add(.hubFilesMenuReveal, key: "r", modifiers: [.command, .option]) { model.revealSelectionInFinder() }
        menu.add(.hubFilesMenuCopyPath, key: "c", modifiers: [.command, .option]) { model.copySelectionPaths() }
        addSidebarItem(to: menu, folders: items.filter(\.isSidebarCandidate).map(\.url), model: model)
        menu.addItem(.separator())
        menu.add(.hubFilesMenuRename, enabled: single && !model.isSearching) { model.beginRenameSelection() }
        menu.add(.hubFilesMenuNewFolder, key: "n", modifiers: [.command, .shift],
                 enabled: !model.isSearching && model.activePane.folderURL != nil) { model.makeNewFolder() }
        menu.addItem(.separator())
        menu.add(.hubFilesMenuTrash, key: "\u{8}", modifiers: [.command]) { model.trashSelection() }
        return menu
    }

    /// The menu for an empty area of a pane: New Folder, adding the folder to the sidebar (or
    /// removing it), and Reveal in Finder and Copy Path for the folder.
    static func background(model: HubFilesModel, pane: HubFilesPane) -> NSMenu? {
        guard let folder = pane.folderURL else { return nil }
        let menu = HubFilesMenu(model: model)
        menu.add(.hubFilesMenuNewFolder, key: "n", modifiers: [.command, .shift]) { model.makeNewFolder() }
        if !HubFilesPath.isVolumeRoot(folder) {
            menu.addItem(.separator())
            let name = model.displayName(for: folder)
            if let id = model.sidebar.store.entryID(for: folder) {
                menu.add(.hubFilesSidebarRemoveNamed(name)) { model.sidebar.remove([id], method: .menu) }
            } else {
                let origin = NSEvent.mouseLocation
                menu.add(.hubFilesSidebarAddNamed(name)) {
                    model.sidebar.addFromCommand([folder], method: .menu, flightOrigin: origin)
                }
            }
            menu.addItem(.separator())
        }
        menu.add(.hubFilesMenuReveal, key: "r", modifiers: [.command, .option]) {
            HubFileOperations.revealInFinder([folder])
            model.shell?.dismissAfterAction()
        }
        menu.add(.hubFilesMenuCopyPath, key: "c", modifiers: [.command, .option]) {
            FilePathCopy.copy([FilePathCopy.path(of: folder)])
        }
        return menu
    }
}

// MARK: - Sidebar

extension HubFilesContextMenu {
    /// A Favorites row: open it in a new tab, reveal or copy its folder, or remove it.
    /// Recents has no folder; a missing or disconnected folder can only be removed.
    static func favorite(_ id: HubFilesSidebarEntryID, model: HubFilesModel) -> NSMenu? {
        let sidebar = model.sidebar
        guard let entry = sidebar.store.entry(id) else { return nil }
        let menu = HubFilesMenu(model: model)
        let folder = sidebar.store.folderURL(for: entry)
        menu.add(.hubFilesSidebarOpenInNewTab, enabled: sidebar.store.location(for: entry) != nil) {
            sidebar.openInNewTab(id)
        }
        menu.addItem(.separator())
        menu.add(.hubFilesMenuReveal, enabled: folder != nil) {
            guard let folder else { return }
            HubFileOperations.revealInFinder([folder])
            model.shell?.dismissAfterAction()
        }
        menu.add(.hubFilesMenuCopyPath, enabled: folder != nil) {
            guard let folder else { return }
            FilePathCopy.copy([FilePathCopy.path(of: folder)])
        }
        menu.addItem(.separator())
        menu.add(.hubFilesSidebarRemove) { sidebar.remove([id], method: .menu) }
        return menu
    }

    /// The Favorites header: brings back built-in places that were removed.
    static func favoritesHeader(model: HubFilesModel) -> NSMenu {
        let menu = HubFilesMenu(model: model)
        menu.add(.hubFilesSidebarRestorePlaces, enabled: !model.sidebar.store.missingPlaces.isEmpty) {
            model.sidebar.restoreDefaultPlaces(method: .headerMenu)
        }
        return menu
    }

    /// "Add to Sidebar" for the selected folders, or "Remove from Sidebar" when all of them are
    /// there already. Nothing when the selection has no folders.
    fileprivate static func addSidebarItem(to menu: HubFilesMenu, folders: [URL], model: HubFilesModel) {
        guard !folders.isEmpty else { return }
        let store = model.sidebar.store
        let ids = folders.compactMap(store.entryID(for:))
        menu.addItem(.separator())
        if ids.count == folders.count {
            menu.add(.hubFilesSidebarRemove) { model.sidebar.remove(ids, method: .menu) }
        } else {
            // The menu opens at the pointer, over the item: the flight starts there.
            let origin = NSEvent.mouseLocation
            menu.add(.hubFilesSidebarAdd, key: "t", modifiers: [.control, .command]) {
                model.sidebar.addFromCommand(folders, method: .menu, flightOrigin: origin)
            }
        }
    }
}

extension HubFileItem {
    /// A folder that can be a sidebar row: not a file, package, app bundle, or drive.
    var isSidebarCandidate: Bool { isDirectory && !isPackage && !HubFilesPath.isVolumeRoot(url) }
}

/// A context menu that runs closures and holds the Hub open while it tracks.
private final class HubFilesMenu: NSMenu, NSMenuDelegate {
    private weak var model: HubFilesModel?
    private var actions: [HubFilesMenuAction] = []
    /// The shell holding the Hub open while this menu tracks; kept so the release stays balanced.
    private var holdingShell: HubShell?

    init(model: HubFilesModel) {
        self.model = model
        super.init(title: "")
        delegate = self
        autoenablesItems = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func add(_ title: LocalizedStringResource, key: String = "", modifiers: NSEvent.ModifierFlags = [],
             enabled: Bool = true, action: @escaping () -> Void) {
        let target = HubFilesMenuAction(action)
        actions.append(target)
        let item = NSMenuItem(title: String(localized: title), action: #selector(HubFilesMenuAction.run),
                              keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.isEnabled = enabled
        addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard holdingShell == nil, let shell = model?.shell else { return }
        holdingShell = shell
        shell.beginHold(.menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        holdingShell?.endHold(.menu)
        holdingShell = nil
    }
}

/// Target object for one menu item's closure.
private final class HubFilesMenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) { self.action = action }

    @objc func run() { action() }
}
