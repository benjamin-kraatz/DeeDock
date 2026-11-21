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
    ///
    /// The file worker first checks each file is still the one its row lists; one that changed is
    /// left alone, its row refreshed, and the toast says so (``reportStale(_:)``).
    func trash(_ items: [FlixItem]? = nil) {
        let items = (items ?? selectedItems).filter { $0.url != nil }
        guard !items.isEmpty else { return }
        reportAction(.trash, items, origin: nil)
        Task { [weak self] in
            let checked = await FlixFileWorker.shared.run { FlixFileOperations.trashable(items) }
            guard let self else { return }
            refreshStale(checked.stale)
            guard !checked.ready.isEmpty else {
                showToast(staleMessage(checked.stale))
                return
            }
            do {
                _ = try await FlixFileActions.trash(checked.ready)
                let ids = Set(checked.ready.map(\.id))
                let next = rowAfterRemoving(ids)
                history.forget(ids)
                selection = next.map { [$0] } ?? []
                cursor = next
                var message = String(localized: .flixToastTrashed(label(for: checked.ready)))
                if !checked.stale.isEmpty { message += " " + staleMessage(checked.stale) }
                showToast(message)
            } catch {
                showToast(error.localizedDescription)
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
    ///
    /// The move runs on the file worker, off the main actor, after checking each file is still the
    /// one its row lists. A move that takes a moment (another volume, a network share) shows a
    /// "Moving…" toast until it finishes.
    func move(_ items: [FlixItem], into folder: URL, undone: (() -> Void)? = nil) {
        let files = items.filter { $0.url != nil }
        guard !files.isEmpty else { return }
        let progress = showProgressSoon(String(localized: .flixToastMoving(label(for: files))))
        Task { [weak self] in
            let report = await FlixFileWorker.shared.run { FlixFileOperations.move(files, into: folder) }
            progress.cancel()
            self?.finishMove(report, into: folder, undone: undone)
        }
    }

    private func finishMove(_ report: FlixMoveReport, into folder: URL, undone: (() -> Void)?) {
        for move in report.moved {
            history.relocate(move.item.id, to: move.to.path, name: move.to.lastPathComponent, identity: move.identity)
        }
        let failedLabel = report.failed.isEmpty ? nil : label(for: report.failed.map(\.item))
        guard !report.moved.isEmpty else {
            if !report.stale.isEmpty { reportStale(report.stale) }
            else if report.failed.count == 1 { showToast(report.failed[0].message) }
            else if let failedLabel { showToast(String(localized: .flixToastNotMoved(failedLabel))) }
            else { clearProgressToast() }
            return
        }
        refreshStale(report.stale)
        let movedItems = report.moved.map(\.item)
        reportAction(.other, movedItems, origin: nil)
        let folderName = FlixFolderNames.displayName(of: folder.path)
        var message = String(localized: .flixToastMoved(label(for: movedItems), folderName))
        if let failedLabel { message += " " + String(localized: .flixToastNotMoved(failedLabel)) }
        if !report.stale.isEmpty { message += " " + staleMessage(report.stale) }
        showToast(message) { [weak self] in
            undone?()
            self?.undoMoves(report.moved)
        }
    }

    /// Renames one file, with Undo. `undone` runs when the toast's Undo is pressed. Runs on the file
    /// worker after checking the file is still the one the row lists.
    func rename(_ item: FlixItem, to name: String, undone: (() -> Void)? = nil) {
        guard item.url != nil else { return }
        Task { [weak self] in
            let outcome = await FlixFileWorker.shared.run { FlixFileOperations.rename(item, to: name) }
            guard let self else { return }
            switch outcome {
            case .renamed(let rename):
                reportAction(.other, [item], origin: nil)
                history.relocate(item.id, to: rename.to.path, name: rename.to.lastPathComponent, identity: rename.identity)
                showToast(String(localized: .flixToastRenamed(rename.to.lastPathComponent))) { [weak self] in
                    undone?()
                    self?.undoMoves([rename])
                }
            case .stale(let stale):
                reportStale([stale])
            case .failed(let message):
                showToast(message)
            }
        }
    }

    /// Puts moved or renamed files back and points their history entries at them again. A file
    /// that changed, moved, or was replaced since stays put with its entry unchanged, and a toast
    /// names it. Runs on the file worker, behind the move it undoes.
    func undoMoves(_ moves: [FlixFileMove]) {
        // Only a move whose history entry still points at the moved file is undone; anything the
        // person moved again inside Flix Files since is left alone.
        let current = moves.filter { history.item($0.item.id)?.path == FlixPaths.standardized($0.to.path) }
        let elsewhere = moves.filter { move in !current.contains { $0.to == move.to } }.map(\.item)
        Task { [weak self] in
            let report = await FlixFileWorker.shared.run { FlixFileOperations.moveBack(current) }
            guard let self else { return }
            for restored in report.restored {
                history.relocate(restored.item.id, to: restored.url.path, name: restored.url.lastPathComponent,
                                 identity: restored.identity)
            }
            let skipped = report.skipped.map(\.item) + elsewhere
            if !skipped.isEmpty { showToast(String(localized: .flixToastUndoSkipped(label(for: skipped)))) }
        }
    }

    // MARK: Changed files

    /// Files a command left alone because they are not what their rows list: refreshes the rows and
    /// says so in a toast.
    func reportStale(_ stale: [FlixStaleFile]) {
        guard !stale.isEmpty else { return }
        refreshStale(stale)
        showToast(staleMessage(stale))
    }

    /// Refreshes rows whose files changed: a row whose file is gone leaves the history (as after the
    /// Trash); any other takes the identity of what is there now, so the next command acts on it.
    private func refreshStale(_ stale: [FlixStaleFile]) {
        let gone = Set(stale.filter { $0.current == nil }.map(\.item.id))
        if !gone.isEmpty { history.forget(gone) }
        history.setIdentities(stale.compactMap { entry in
            guard entry.current != nil, let path = entry.item.path else { return nil }
            return (entry.item.id, path, entry.current)
        })
    }

    private func staleMessage(_ stale: [FlixStaleFile]) -> String {
        let named = label(for: stale.map(\.item))
        return stale.allSatisfy(\.wasUnchecked) ? String(localized: .flixToastNotCheckedYet(named))
            : String(localized: .flixToastChangedSince(named))
    }

    /// Shows `message` as a toast if the work it describes is still running after a moment, so a
    /// quick move shows only its result. Cancel the returned task when the work ends.
    private func showProgressSoon(_ message: String) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            showToast(message)
            progressToastID = toast?.id
        }
    }

    /// Hides the "Moving…" toast when the work finished with nothing to report.
    private func clearProgressToast() {
        guard let id = progressToastID, toast?.id == id else { return }
        toast = nil
        progressToastID = nil
    }

    /// Opens files with an app, for a drop on an app favorite.
    func open(_ items: [FlixItem], withApplicationAt app: URL) {
        reportAction(.open, items, origin: nil)
        FlixFileActions.open(items.compactMap(\.url), withApplicationAt: app)
        close?(false)
    }

    /// Keeps dropped files or pages as items: a deliberate save.
    ///
    /// Pages are kept at once. What each file is (its type, name, and identity) is read on the file
    /// worker, off the main actor, because a file dropped from a share can take seconds to answer;
    /// the files join the list, and the toast shows, when that read is done.
    func keep(files: [URL], links: [URL]) {
        let now = Date.now
        var keptLinks = 0
        for original in links where !original.isFileURL {
            // Only web pages, without sign-in tokens or session parameters.
            guard let url = FlixURLSanitizer.sanitize(original) else { continue }
            let link = FlixLink(url: url, title: nil, browserBundleIdentifier: nil)
            reportLinkKept(link, removedSecrets: FlixURLSanitizer.removedSecretCount(original))
            history.record(FlixActivityEvent(link: link, name: link.host, kind: .link, activity: .link, date: now))
            keptLinks += 1
        }
        let fileURLs = files.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            finishKeeping(keptLinks)
            return
        }
        Task { [weak self] in
            let events = await FlixFileWorker.shared.run { fileURLs.map { Self.keptEvent(for: $0, date: now) } }
            guard let self else { return }
            events.forEach { self.history.record($0) }
            finishKeeping(keptLinks + events.count)
        }
    }

    /// A kept file as an event. The person handed this file over, so reading what it is now is
    /// theirs to ask for. Reads the disk: call it on the file worker.
    nonisolated static func keptEvent(for url: URL, date: Date) -> FlixActivityEvent {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey, .localizedNameKey])
        return FlixActivityEvent(path: url.path, name: values?.localizedName ?? url.lastPathComponent,
                                 kind: FlixItemKind.classify(contentType: values?.contentType,
                                                             isDirectory: values?.isDirectory == true,
                                                             isPackage: values?.isPackage == true,
                                                             isScreenshot: false),
                                 activity: .kept, date: date,
                                 contentTypeIdentifier: values?.contentType?.identifier,
                                 fileIdentity: FlixFileIdentity.of(url))
    }

    private func finishKeeping(_ kept: Int) {
        guard kept > 0 else { return }
        filter = .all
        selectFirst()
        showToast(String(localized: .flixToastKept(kept)))
    }

    /// Drops onto a sidebar favorite: a folder moves, an app opens.
    ///
    /// A folder move checks each file against the identity its row listed when the drag began (the
    /// drag session keeps it), so a row whose file was replaced during or before the drag moves
    /// nothing (`FlixFileOperations.move`).
    func drop(_ ids: [FlixItem.ID], on favorite: FlixFavorite) {
        var items = ids.compactMap(history.item)
        guard !items.isEmpty else { return }
        if favorite.kind == .folder, let dragged = FlixDragSession.draggedFiles(on: NSPasteboard(name: .drag)) {
            items = items.map { item in
                var item = item
                if let path = item.path, let listed = dragged.identities[FlixPaths.standardized(path)] {
                    item.fileIdentity = listed
                }
                return item
            }
        }
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

    /// Applies the checked Tidy suggestions with one Undo, on the file worker. Each file is checked
    /// once before its rename and move; one that changed is left alone and named in the toast.
    func applyTidy(_ suggestions: [FlixTidySuggestion]) {
        let shown = intelligence.tidy.filter { history.item($0.itemID) != nil }
        var report = AnalyticsFlixTidy(shownMoves: shown.count { $0.moveTo != nil },
                                       shownRenames: shown.count { $0.rename != nil })
        report.unchecked = max(0, shown.count - suggestions.count)
        tidyApplied = true
        sheet = nil
        let work = suggestions.compactMap { suggestion in
            history.item(suggestion.itemID).map { (item: $0, rename: suggestion.rename, moveTo: suggestion.moveTo) }
        }
        let progress = showProgressSoon(String(localized: .flixToastTidying))
        Task { [weak self] in
            let outcomes = await FlixFileWorker.shared.run {
                work.map { FlixFileOperations.tidy($0.item, rename: $0.rename, moveTo: $0.moveTo) }
            }
            progress.cancel()
            self?.finishTidy(outcomes, report: report)
        }
    }

    private func finishTidy(_ outcomes: [FlixFileOperations.TidyOutcome], report: AnalyticsFlixTidy) {
        var report = report
        // One combined move per file, from where it was to where Tidy left it, so Undo checks the
        // file's identity once and puts it straight back.
        var undo: [FlixFileMove] = []
        for outcome in outcomes {
            if outcome.renamed != nil { report.appliedRenames += 1 }
            if outcome.moved != nil { report.appliedMoves += 1 }
            if let last = outcome.moved ?? outcome.renamed {
                history.relocate(outcome.itemID, to: last.to.path, name: last.to.lastPathComponent, identity: last.identity)
            }
            if let move = outcome.undo { undo.append(move) }
        }
        let stale = outcomes.compactMap(\.stale)
        refreshStale(stale)
        guard !undo.isEmpty else {
            Analytics.track(.flixTidy(report))
            if !stale.isEmpty { showToast(staleMessage(stale)) } else { clearProgressToast() }
            return
        }
        var message = String(localized: .flixToastTidied(undo.count))
        if !stale.isEmpty { message += " " + staleMessage(stale) }
        showToast(message) { [weak self] in self?.undoMoves(undo) }
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
