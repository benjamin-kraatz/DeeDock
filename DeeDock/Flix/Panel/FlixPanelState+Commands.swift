import AppKit
import UniformTypeIdentifiers

/// The commands behind rows, the context menu, keys, sheets, and drops.
extension FlixPanelState {
    /// "“Invoice.pdf”" for one item, "3 items" for more.
    func label(for items: [FlixItem]) -> String {
        items.count == 1 ? String(localized: .flixLabelQuoted(items[0].name))
            : String(localized: .flixLabelItems(items.count))
    }

    /// Opens items. `origin` is where they were opened from; nil means the selection's place.
    func open(_ items: [FlixItem]? = nil, origin: FlixActionOrigin? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        reportAction(.open, items, origin: origin)
        FlixFileActions.open(items)
        close?(false)
    }

    func reveal(_ items: [FlixItem]? = nil) {
        let items = (items ?? selectedItems).filter { $0.url != nil }
        guard !items.isEmpty else { return }
        reportAction(.reveal, items, origin: nil)
        FlixFileActions.reveal(items)
        close?(false)
    }

    func quickLook() {
        let items = selectedItems.filter { $0.url != nil }
        guard !items.isEmpty else { return }
        reportAction(.quickLook, items, origin: nil)
        toggleQuickLook?(items.compactMap(\.url))
    }

    func copy(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        reportAction(.copy, items, origin: nil)
        FlixFileActions.copy(items)
        showToast(String(localized: .flixToastCopied(label(for: items))))
    }

    func copyPaths(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        reportAction(.copy, items, origin: nil)
        FlixFileActions.copyPaths(items)
        showToast(String(localized: .flixToastCopiedPath(items.count)))
    }

    /// Flags the selection, or unflags it when the first item is flagged already.
    func toggleFlag(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard let first = items.first else { return }
        let flag = !first.isFlagged
        reportAction(flag ? .flag : .other, items, origin: nil)
        history.setFlagged(flag, for: Set(items.map(\.id)))
        showToast(String(localized: flag ? .flixToastFlagged(label(for: items)) : .flixToastUnflagged(label(for: items))))
    }

    func addToFavorites(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        let favorites = items.compactMap(FlixFavorite.make)
        guard !favorites.isEmpty else { return }
        reportAction(.favorite, items, origin: nil)
        favorites.forEach(history.addFavorite)
        showToast(String(localized: .flixToastFavoriteAdded(favorites.count == 1 ? favorites[0].name
            : String(localized: .flixLabelItems(favorites.count)))))
    }

    /// Removes items from Flix Files, with Undo. The files stay where they are.
    func remove(_ items: [FlixItem]? = nil) {
        let items = items ?? selectedItems
        guard !items.isEmpty else { return }
        reportAction(.remove, items, origin: nil)
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
        reportAction(.trash, items, origin: nil)
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
        reportAction(.other, items, origin: nil)
        if sendToShelf?(urls) == true {
            showToast(String(localized: .flixToastShelf(label(for: items))))
        } else {
            showToast(String(localized: .flixToastShelfFailed))
        }
    }

    /// Moves files into a folder, with Undo for the ones that moved. Their history entries follow
    /// them; a file that could not be moved keeps its entry, and the toast says so. `undone` runs
    /// when the toast's Undo is pressed.
    func move(_ items: [FlixItem], into folder: URL, undone: (() -> Void)? = nil) {
        let report = FlixFileActions.move(items, into: folder)
        let failedLabel = report.failed.isEmpty ? nil : label(for: report.failed.map(\.item))
        guard !report.moved.isEmpty else {
            if report.failed.count == 1 { showToast(report.failed[0].message) }
            else if let failedLabel { showToast(String(localized: .flixToastNotMoved(failedLabel))) }
            return
        }
        let movedItems = report.moved.map(\.item)
        reportAction(.other, movedItems, origin: nil)
        for move in report.moved { history.relocate(move.item.id, to: move.to.path, name: move.to.lastPathComponent) }
        let folderName = FileManager.default.displayName(atPath: folder.path)
        var message = String(localized: .flixToastMoved(label(for: movedItems), folderName))
        if let failedLabel { message += " " + String(localized: .flixToastNotMoved(failedLabel)) }
        showToast(message) { [weak self] in
            undone?()
            self?.undoMoves(report.moved)
        }
    }

    /// Renames one file, with Undo. `undone` runs when the toast's Undo is pressed.
    func rename(_ item: FlixItem, to name: String, undone: (() -> Void)? = nil) {
        do {
            guard let rename = try FlixFileActions.rename(item, to: name) else { return }
            reportAction(.other, [item], origin: nil)
            history.relocate(item.id, to: rename.to.path, name: rename.to.lastPathComponent)
            showToast(String(localized: .flixToastRenamed(rename.to.lastPathComponent))) { [weak self] in
                undone?()
                self?.undoMoves([rename])
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// Puts moved or renamed files back and points their history entries at them again. A file
    /// that changed, moved, or was replaced since stays put with its entry unchanged, and a toast
    /// names it.
    func undoMoves(_ moves: [FlixFileMove]) {
        // Only a move whose history entry still points at the moved file is undone; anything the
        // person moved again inside Flix Files since is left alone.
        let current = moves.filter { history.item($0.item.id)?.path == FlixPaths.standardized($0.to.path) }
        let report = FlixFileActions.moveBack(current)
        for restored in report.restored {
            history.relocate(restored.item.id, to: restored.url.path, name: restored.url.lastPathComponent)
        }
        let skipped = report.skipped.map(\.item) + moves.filter { move in !current.contains { $0.to == move.to } }.map(\.item)
        if !skipped.isEmpty { showToast(String(localized: .flixToastUndoSkipped(label(for: skipped)))) }
    }

    /// Opens files with an app, for a drop on an app favorite.
    func open(_ items: [FlixItem], withApplicationAt app: URL) {
        reportAction(.open, items, origin: nil)
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
        for original in links where !original.isFileURL {
            // Only web pages, without sign-in tokens or session parameters.
            guard let url = FlixURLSanitizer.sanitize(original) else { continue }
            let link = FlixLink(url: url, title: nil, browserBundleIdentifier: nil)
            reportLinkKept(link, removedSecrets: FlixURLSanitizer.removedSecretCount(original))
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
        reportFavoriteDrop(items, on: favorite)
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
        reportAction(.other, [item], origin: nil)
        if searchActive { setSearchActive(false) }
        intelligence.showMoreLikeThis(item, in: history.items)
    }

    func showThread(of item: FlixItem) {
        guard let thread = intelligence.thread(containing: item.id) else { return }
        filter = .thread(thread.id)
    }

    /// Opens Ask Robi for `items`. `origin` is where it was opened from (a thread card), else the
    /// selection's place.
    func askRobi(_ items: [FlixItem]? = nil, origin: FlixActionOrigin? = nil) {
        let items = items ?? selectedItems
        guard intelligence.canAskRobi, !items.isEmpty else { return }
        robiOrigin = origin
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
        let shown = intelligence.tidy.filter { history.item($0.itemID) != nil }
        var report = AnalyticsFlixTidy(shownMoves: shown.count { $0.moveTo != nil },
                                       shownRenames: shown.count { $0.rename != nil })
        report.unchecked = max(0, shown.count - suggestions.count)
        // One combined move per file, from where it was to where Tidy left it, so Undo checks the
        // file's identity once and puts it straight back.
        var undo: [FlixFileMove] = []
        for suggestion in suggestions {
            guard var item = history.item(suggestion.itemID), let original = item.url else { continue }
            let before = item
            var last: FlixFileMove?
            if let name = suggestion.rename, let renamed = try? FlixFileActions.rename(item, to: name) {
                history.relocate(item.id, to: renamed.to.path, name: renamed.to.lastPathComponent)
                item.path = renamed.to.path
                last = renamed
                report.appliedRenames += 1
            }
            if let folder = suggestion.moveTo,
               let move = FlixFileActions.move([item], into: URL(fileURLWithPath: folder)).moved.first {
                history.relocate(item.id, to: move.to.path, name: move.to.lastPathComponent)
                last = move
                report.appliedMoves += 1
            }
            if let last, last.to != original {
                undo.append(FlixFileMove(item: before, from: original, to: last.to, identity: last.identity))
            }
        }
        tidyApplied = true
        sheet = nil
        guard !undo.isEmpty else {
            Analytics.track(.flixTidy(report))
            return
        }
        showToast(String(localized: .flixToastTidied(undo.count))) { [weak self] in self?.undoMoves(undo) }
        // After the toast: Undo, a newer toast, or its timeout settles it (`settleTidy(undone:)`).
        pendingTidy = report
    }

    /// Adds a Smart Filter and shows it. `generator` says what wrote one made from a sentence.
    func addSmartFilter(_ filter: FlixSmartFilter, origin: FlixSmartFilterOrigin = .manual,
                        generator: AnalyticsFlixGenerator? = nil) {
        var filter = filter
        filter.origin = origin
        history.saveSmartFilter(filter)
        reportSmartFilterCreated(filter, generator: generator)
        sheet = nil
        intelligence.resetSmartFilterDraft()
        self.filter = .smart(filter.id)
    }

    /// Deletes a Smart Filter from the sidebar.
    func removeSmartFilter(_ id: FlixSmartFilter.ID) {
        guard let removed = history.smartFilters.first(where: { $0.id == id }) else { return }
        if filter == .smart(id) { filter = .all }
        history.removeSmartFilter(id)
        Analytics.track(.flixSmartFilterRemoved(source: removed.origin?.analytics ?? .manual))
    }

    /// Accepts a row's ✦ folder suggestion, with Undo.
    func moveToSuggestedFolder(_ item: FlixItem) {
        guard let folder = intelligence.annotation(for: item.id)?.folderSuggestion else { return }
        Analytics.track(.flixSuggestionActed(.move, action: .accepted, itemKind: item.analyticsKind))
        move([item], into: URL(fileURLWithPath: folder)) {
            Analytics.track(.flixSuggestionActed(.move, action: .undone, itemKind: item.analyticsKind))
        }
    }

    /// Accepts a row's ✦ rename suggestion, with Undo.
    func renameToSuggestion(_ item: FlixItem) {
        guard let name = intelligence.annotation(for: item.id)?.renameSuggestion else { return }
        Analytics.track(.flixSuggestionActed(.rename, action: .accepted, itemKind: item.analyticsKind))
        rename(item, to: name) {
            Analytics.track(.flixSuggestionActed(.rename, action: .undone, itemKind: item.analyticsKind))
        }
    }

    /// Shows or hides a row's older versions. Showing them reports `flix_versions_expanded`.
    func toggleVersions(_ group: String, count: Int) {
        if expandedVersions.contains(group) {
            expandedVersions.remove(group)
        } else {
            expandedVersions.insert(group)
            Analytics.track(.flixVersionsExpanded(versionCount: count))
        }
    }

    /// Asks Robi about `items`. `suggestionIndex` is the position of a suggested question, nil for
    /// a typed one; only that position is reported, never the text.
    func ask(_ question: String, about items: [FlixItem], suggestionIndex: Int?) {
        reportAction(.robi, items, origin: robiOrigin)
        if robiOrigin == .threadCard, let thread = items.first.flatMap({ intelligence.thread(containing: $0.id) }) {
            reportThread(.robi, thread)
        }
        intelligence.ask(question, about: items, question: AnalyticsFlixRobiQuestion(suggestionIndex: suggestionIndex))
    }

    /// Runs a morning card button.
    func runMorningAction(_ action: FlixMorningCard.Action, card: FlixMorningCard) {
        switch action.target {
        case .open(let ids):
            metrics?.morningActed(.reopen, card: card)
            intelligence.dismissMorning()
            open(ids.compactMap(history.item), origin: .morningCard)
        case .filter(let target):
            metrics?.morningActed(.thread, card: card)
            intelligence.dismissMorning()
            filter = target
        }
    }

    /// The morning card's ✕.
    func dismissMorning(_ card: FlixMorningCard) {
        metrics?.morningActed(.dismiss, card: card)
        intelligence.dismissMorning()
    }

    /// The sidebar tip's Make Filter.
    func acceptFilterTip(_ tip: FlixFilterTip) {
        Analytics.track(.flixTipActed(.smartFilter, action: .accepted))
        intelligence.dismissFilterTip()
        addSmartFilter(tip.proposal, origin: .tip)
    }

    /// The sidebar tip's ✕.
    func dismissFilterTip() {
        Analytics.track(.flixTipActed(.smartFilter, action: .dismissed))
        intelligence.dismissFilterTip()
    }

    /// A thread card's Open All.
    func openThread(_ thread: FlixThread) {
        reportThread(.openAll, thread)
        open(thread.memberIDs.compactMap(history.item), origin: .threadCard)
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
