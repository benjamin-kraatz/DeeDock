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
        menu.addItem(.separator())
        menu.add(.hubFilesMenuRename, enabled: single && !model.isSearching) { model.beginRenameSelection() }
        menu.add(.hubFilesMenuNewFolder, key: "n", modifiers: [.command, .shift],
                 enabled: !model.isSearching && model.activePane.folderURL != nil) { model.makeNewFolder() }
        menu.addItem(.separator())
        menu.add(.hubFilesMenuTrash, key: "\u{8}", modifiers: [.command]) { model.trashSelection() }
        return menu
    }

    /// The menu for an empty area of a pane: New Folder and Reveal in Finder for the folder.
    static func background(model: HubFilesModel, pane: HubFilesPane) -> NSMenu? {
        guard let folder = pane.folderURL else { return nil }
        let menu = HubFilesMenu(model: model)
        menu.add(.hubFilesMenuNewFolder, key: "n", modifiers: [.command, .shift]) { model.makeNewFolder() }
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
