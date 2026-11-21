import AppKit
import SwiftUI

/// The row context menu, built in AppKit from the panel state at the moment it opens.
///
/// Every entry carries its SF Symbol, like DOKK's other menus; the ✦ entries carry the mark in the
/// intelligence violet in that column instead of in their titles.
///
/// ✦ entries appear only when their slot has something to offer (a provider, an annotation, a
/// thread), in the mockup's order: Open, Show in Finder; Ask Robi…, More like this, Rename to…,
/// Move to…, Show Thread; Copy, Copy Path, Send to Shelf, Flag; Add to Favorites; Remove from
/// Flix Files, Move to Trash.
@MainActor
final class FlixContextMenu: NSObject {
    private let state: FlixPanelState
    private let items: [FlixItem]
    /// Kept alive while the menu tracks.
    private static var current: FlixContextMenu?

    private init(state: FlixPanelState, items: [FlixItem]) {
        self.state = state
        self.items = items
    }

    /// The menu for the current selection, or nil when nothing is selected.
    static func make(for state: FlixPanelState) -> NSMenu? {
        let items = state.selectedItems
        guard !items.isEmpty else { return nil }
        let builder = FlixContextMenu(state: state, items: items)
        current = builder
        return builder.build()
    }

    private func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let one = items.count == 1 ? items[0] : nil
        let annotation = one.flatMap { state.intelligence.annotation(for: $0.id) }
        let files = items.filter { $0.url != nil }

        add(items.count > 1 ? String(localized: .flixMenuOpenCount(items.count)) : String(localized: .flixMenuOpen),
            key: "\r", symbol: "arrow.up.right.square", action: #selector(open), to: menu)
        add(String(localized: .flixMenuShowInFinder), key: "\r", modifiers: .command, symbol: "folder", action: #selector(reveal),
            to: menu, enabled: !files.isEmpty)
        menu.addItem(.separator())

        var intelligence: [NSMenuItem] = []
        if state.intelligence.canAskRobi {
            intelligence.append(intelligent(String(localized: .flixMenuAskRobi), key: "r", modifiers: .command,
                                     action: #selector(askRobi)))
        }
        if one != nil, state.intelligence.canShowMoreLikeThis {
            intelligence.append(intelligent(String(localized: .flixMenuMoreLikeThis), action: #selector(moreLikeThis)))
        }
        if one != nil, let rename = annotation?.renameSuggestion {
            intelligence.append(intelligent(String(localized: .flixMenuRenameTo(rename)), action: #selector(renameSuggested)))
        }
        if one != nil, let folder = annotation?.folderSuggestion {
            let name = FlixFolderNames.displayName(of: folder)
            intelligence.append(intelligent(String(localized: .flixMenuMoveTo(name)), action: #selector(moveSuggested)))
        }
        if let one, let thread = state.intelligence.thread(containing: one.id) {
            intelligence.append(intelligent(String(localized: .flixMenuShowThread(thread.name)), action: #selector(showThread)))
        }
        if !intelligence.isEmpty {
            intelligence.forEach(menu.addItem)
            menu.addItem(.separator())
        }

        if one?.url != nil {
            add(String(localized: .flixMenuRename), symbol: "pencil", action: #selector(rename), to: menu)
        }
        add(String(localized: .flixMenuCopy), key: "c", modifiers: .command, symbol: "doc.on.doc", action: #selector(copyItems), to: menu)
        add(String(localized: .flixMenuCopyPath), key: "c", modifiers: [.command, .option], symbol: "point.topleft.down.to.point.bottomright.curvepath",
            action: #selector(copyPath), to: menu)
        add(String(localized: .flixMenuSendToShelf), symbol: "tray.and.arrow.down", action: #selector(shelf), to: menu,
            enabled: !files.isEmpty)
        let flagged = items.first?.isFlagged == true
        add(String(localized: flagged ? .flixMenuUnflag : .flixMenuFlag), key: "k", modifiers: .command,
            symbol: flagged ? "flag.slash" : "flag", action: #selector(flag), to: menu)
        add(String(localized: .flixMenuAddToFavorites), key: "d", modifiers: .command, symbol: "star", action: #selector(favorite),
            to: menu, enabled: !files.isEmpty)
        menu.addItem(.separator())
        add(String(localized: .flixMenuRemove), key: "\u{8}", modifiers: [], symbol: "minus.circle", action: #selector(remove), to: menu)
        add(String(localized: .flixMenuMoveToTrash), key: "\u{8}", modifiers: .command, symbol: "trash", action: #selector(trash),
            to: menu, enabled: !files.isEmpty)
        return menu
    }

    private func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], symbol: String? = nil,
                      action: Selector, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        entry.isEnabled = enabled
        entry.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return entry
    }

    /// A ✦ entry: the mark as a violet symbol in the image column, or in the title if the symbol
    /// is missing.
    private func intelligent(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [],
                             action: Selector) -> NSMenuItem {
        let mark = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor(FlixStyle.aiViolet)]))
        let entry = item(mark == nil ? "✦ " + title : title, key: key, modifiers: modifiers, action: action)
        entry.image = mark
        return entry
    }

    private func add(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], symbol: String? = nil,
                     action: Selector, to menu: NSMenu, enabled: Bool = true) {
        menu.addItem(item(title, key: key, modifiers: modifiers, symbol: symbol, action: action, enabled: enabled))
    }

    @objc private func open() { state.open(items) }
    @objc private func reveal() { state.reveal(items) }
    @objc private func askRobi() { state.askRobi(items) }
    @objc private func moreLikeThis() { if let first = items.first { state.showMoreLikeThis(first) } }
    @objc private func renameSuggested() {
        guard let item = items.first else { return }
        state.renameToSuggestion(item)
    }
    @objc private func moveSuggested() {
        guard let item = items.first else { return }
        state.moveToSuggestedFolder(item)
    }
    @objc private func showThread() { if let first = items.first { state.showThread(of: first) } }
    @objc private func rename() { if let first = items.first { state.sheet = .rename(first.id) } }
    @objc private func copyItems() { state.copy(items) }
    @objc private func copyPath() { state.copyPaths(items) }
    @objc private func shelf() { state.sendToShelf(items) }
    @objc private func flag() { state.toggleFlag(items) }
    @objc private func favorite() { state.addToFavorites(items) }
    @objc private func remove() { state.remove(items) }
    @objc private func trash() { state.trash(items) }
}
