import AppKit
import UniformTypeIdentifiers

/// The commands behind rows, the context menu, keys, sheets, and drops.
extension FlixPanelState {
    /// "“Invoice.pdf”" for one item, "3 items" for more.
    func label(for items: [FlixItem]) -> String {
        items.count == 1 ? String(localized: .flixLabelQuoted(items[0].name))
            : String(localized: .flixLabelItems(items.count))
    }

    func open(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        FlixFileActions.open(items)
        close?(false)
    }

    func reveal(_ items: [FlixItem]? = nil) {
        let items = (items ?? selectedItems).filter { $0.url != nil }
        guard !items.isEmpty else { return }
        FlixFileActions.reveal(items)
        close?(false)
    }

    func quickLook() {
        let urls = selectedItems.compactMap(\.url)
        guard !urls.isEmpty else { return }
        toggleQuickLook?(urls)
    }

    func copy(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        FlixFileActions.copy(items)
        showToast(String(localized: .flixToastCopied(label(for: items))))
    }

    func copyPaths(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        FlixFileActions.copyPaths(items)
        showToast(String(localized: .flixToastCopiedPath(items.count)))
    }

    /// Flags the selection, or unflags it when the first item is flagged already.
    func toggleFlag(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard let first = items.first else { return }
        let flag = !first.isFlagged
        history.setFlagged(flag, for: Set(items.map(\.id)))
        showToast(String(localized: flag ? .flixToastFlagged(label(for: items)) : .flixToastUnflagged(label(for: items))))
    }

    func addToFavorites(_ items: [FlixItem]? = nil) {
        let favorites = (items ?? selectedItems).compactMap(FlixFavorite.make)
        guard !favorites.isEmpty else { return }
        favorites.forEach(history.addFavorite)
        showToast(String(localized: .flixToastFavoriteAdded(favorites.count == 1 ? favorites[0].name
            : String(localized: .flixLabelItems(favorites.count)))))
    }

    /// Removes items from Flix Files, with Undo. The files stay where they are.
    func remove(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        let next = rowAfterRemoving(Set(items.map(\.id)))
        let removed = history.remove(Set(items.map(\.id)))
        selection = next.map { [$0] } ?? []
        cursor = next
        showToast(String(localized: .flixToastRemoved(label(for: items)))) { [weak self] in
            self?.history.restore(removed)
        }
    }

    /// Moves files to the Trash. Undo is Finder's Put Back, so the toast offers none.
    func trash(_ items: [FlixItem]? = nil) {
        let items = (items ?? selectedItems).filter { $0.url != nil }
        guard !items.isEmpty else { return }
        let message = String(localized: .flixToastTrashed(label(for: items)))
        Task { [weak self] in
            do {
                _ = try await FlixFileActions.trash(items)
                guard let self else { return }
                let next = rowAfterRemoving(Set(items.map(\.id)))
                history.forget(Set(items.map(\.id)))
                selection = next.map { [$0] } ?? []
                cursor = next
                showToast(message)
            } catch {
                self?.showToast(error.localizedDescription)
            }
        }
    }

    func sendToShelf(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        let urls = items.compactMap(\.url)
        guard !urls.isEmpty else { return }
        if sendToShelf?(urls) == true {
            showToast(String(localized: .flixToastShelf(label(for: items))))
        } else {
            showToast(String(localized: .flixToastShelfFailed))
        }
    }

    /// Moves files into a folder, with Undo. Their history entries follow them.
    func move(_ items: [FlixItem], into folder: URL) {
        do {
            let moves = try FlixFileActions.move(items, into: folder)
            guard !moves.isEmpty else { return }
            for move in moves { history.relocate(move.item.id, to: move.to.path, name: move.to.lastPathComponent) }
            let folderName = FileManager.default.displayName(atPath: folder.path)
            showToast(String(localized: .flixToastMoved(label(for: items), folderName))) { [weak self] in
                guard let self else { return }
                for restored in FlixFileActions.moveBack(moves) {
                    history.relocate(restored.item.id, to: restored.url.path, name: restored.url.lastPathComponent)
                }
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Renames one file, with Undo.
    func rename(_ item: FlixItem, to name: String) {
        do {
            guard let original = item.url, let renamed = try FlixFileActions.rename(item, to: name) else { return }
            history.relocate(item.id, to: renamed.path, name: renamed.lastPathComponent)
            showToast(String(localized: .flixToastRenamed(renamed.lastPathComponent))) { [weak self] in
                guard let self, let current = history.item(item.id),
                      let back = try? FlixFileActions.rename(current, to: original.lastPathComponent) else { return }
                history.relocate(item.id, to: back.path, name: back.lastPathComponent)
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Opens files with an app, for a drop on an app favorite.
    func open(_ items: [FlixItem], withApplicationAt app: URL) {
        FlixFileActions.open(items.compactMap(\.url), withApplicationAt: app)
        close?(false)
    }

    /// Keeps dropped files or pages as items: a deliberate save.
    func keep(files: [URL], links: [URL]) {
        let now = Date.now
        var kept = 0
        for url in files where url.isFileURL {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey, .localizedNameKey])
            history.record(FlixActivityEvent(path: url.path, name: values?.localizedName ?? url.lastPathComponent,
                                             kind: FlixItemKind.classify(contentType: values?.contentType,
                                                                         isDirectory: values?.isDirectory == true,
                                                                         isPackage: values?.isPackage == true,
                                                                         isScreenshot: false),
                                             activity: .kept, date: now,
                                             contentTypeIdentifier: values?.contentType?.identifier))
            kept += 1
        }
        for url in links where !url.isFileURL {
            // Only web pages, without sign-in tokens or session parameters.
            guard let url = FlixURLSanitizer.sanitize(url) else { continue }
            let link = FlixLink(url: url, title: nil, browserBundleIdentifier: nil)
            history.record(FlixActivityEvent(link: link, name: link.host, kind: .link, activity: .link, date: now))
            kept += 1
        }
        guard kept > 0 else { return }
        filter = .all
        selectFirst()
        showToast(String(localized: .flixToastKept(kept)))
    }

    /// Drops onto a sidebar favorite: a folder moves, an app opens.
    func drop(_ ids: [FlixItem.ID], on favorite: FlixFavorite) {
        let items = ids.compactMap(history.item)
        guard !items.isEmpty else { return }
        switch favorite.kind {
        case .folder: move(items, into: favorite.url)
        case .app: open(items, withApplicationAt: favorite.url)
        case .file: break
        }
    }

    /// Clicks on a favorite: folders filter, apps and files open.
    func activate(_ favorite: FlixFavorite) {
        switch favorite.kind {
        case .folder: filter = .favorite(favorite.id)
        case .app, .file:
            NSWorkspace.shared.open(favorite.url)
            close?(false)
        }
    }

    // MARK: Intelligence-backed commands

    func showMoreLikeThis(_ item: FlixItem) {
        if searchActive { setSearchActive(false) }
        intelligence.showMoreLikeThis(item, in: history.items)
    }

    func showThread(of item: FlixItem) {
        guard let thread = intelligence.thread(containing: item.id) else { return }
        filter = .thread(thread.id)
    }

    func askRobi(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard intelligence.canAskRobi, !items.isEmpty else { return }
        intelligence.resetRobi()
        sheet = .askRobi(items.map(\.id))
    }

    func openTidy() {
        guard intelligence.canTidy else { return }
        intelligence.refreshTidy(items: history.items)
        sheet = .tidy
    }

    /// Applies the checked Tidy suggestions with one Undo.
    func applyTidy(_ suggestions: [FlixTidySuggestion]) {
        var undo: [() -> Void] = []
        for suggestion in suggestions {
            guard var item = history.item(suggestion.itemID), let original = item.url else { continue }
            if let name = suggestion.rename, let renamed = try? FlixFileActions.rename(item, to: name) {
                history.relocate(item.id, to: renamed.path, name: renamed.lastPathComponent)
                item.path = renamed.path
            }
            if let folder = suggestion.moveTo, let moves = try? FlixFileActions.move([item], into: URL(fileURLWithPath: folder)),
               let move = moves.first {
                history.relocate(item.id, to: move.to.path, name: move.to.lastPathComponent)
            }
            let id = item.id
            undo.append { [weak self] in
                guard let self, let current = history.item(id)?.url, current != original,
                      (try? FileManager.default.moveItem(at: current, to: original)) != nil else { return }
                history.relocate(id, to: original.path, name: original.lastPathComponent)
            }
        }
        sheet = nil
        guard !undo.isEmpty else { return }
        showToast(String(localized: .flixToastTidied(undo.count))) { undo.forEach { $0() } }
    }

    /// Adds a Smart Filter and shows it.
    func addSmartFilter(_ filter: FlixSmartFilter) {
        history.saveSmartFilter(filter)
        sheet = nil
        intelligence.resetSmartFilterDraft()
        self.filter = .smart(filter.id)
    }

    func togglePin() {
        isPinned.toggle()
        showToast(String(localized: isPinned ? .flixToastPinned : .flixToastUnpinned))
    }

    /// The row to select after the selection disappears: the next one down, else the one above.
    private func rowAfterRemoving(_ ids: Set<FlixItem.ID>) -> FlixItem.ID? {
        let order = navigationOrder
        guard let last = order.lastIndex(where: ids.contains) else { return order.first }
        return order[(last + 1)...].first { !ids.contains($0) } ?? order[..<last].last { !ids.contains($0) }
    }
}
