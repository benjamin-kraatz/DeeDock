import AppKit

/// File actions: open, Quick Look, reveal, copy path, rename, new folder, trash, and transfers.
extension HubFilesModel {
    // MARK: Open

    /// Opens a folder in place or a file in its default app.
    ///
    /// Opening a file hands focus to another app, so an anchored Hub closes afterwards.
    func open(_ item: HubFileItem, in pane: HubFilesPane) {
        if item.isDirectory {
            show(.folder(normalizing: item.url), in: pane)
        } else {
            HubFileOperations.open([item.url])
            shell?.dismissAfterAction()
        }
    }

    /// Opens a search result: a folder shows in the active pane and ends the search; a file opens.
    func openSearchResult(_ item: HubFileItem) {
        let scope: AnalyticsHubSearchScope = searchScope == .thisMac ? .thisMac : .folder
        Analytics.track(.hubFileSearchResultOpened(scope: scope, isFolder: item.isDirectory))
        if item.isDirectory {
            show(.folder(normalizing: item.url))
        } else {
            HubFileOperations.open([item.url])
            shell?.dismissAfterAction()
        }
    }

    /// Return / ⌘↓ / Open: a single folder opens in place, files open in their apps.
    func openSelection() {
        let items = actionableItems
        guard !items.isEmpty else { return }
        if isSearching {
            if let first = items.first, items.count == 1 { openSearchResult(first); return }
        } else if items.count == 1, let folder = items.first, folder.isDirectory {
            open(folder, in: activePane)
            return
        }
        let files = items.filter { !$0.isDirectory }
        guard !files.isEmpty else { return }
        HubFileOperations.open(files.map(\.url))
        shell?.dismissAfterAction()
    }

    // MARK: Quick Look, reveal, copy path

    func toggleQuickLook() {
        quickLook.toggle()
    }

    func revealSelectionInFinder() {
        let urls = actionableItems.map(\.url)
        let targets = urls.isEmpty ? activePane.folderURL.map { [$0] } ?? [] : urls
        guard !targets.isEmpty else { return }
        HubFileOperations.revealInFinder(targets)
        shell?.dismissAfterAction()
    }

    func copySelectionPaths() {
        FilePathCopy.copy(actionableItems.map { FilePathCopy.path(of: $0.url) })
    }

    // MARK: Rename and new folder

    /// Shows the inline rename field for the single selected item in the active pane.
    func beginRenameSelection() {
        guard !isSearching, let item = activePane.selectedItems.first, activePane.selection.count == 1 else { return }
        activePane.beginRename(item.url, name: item.url.lastPathComponent)
    }

    /// Applies the rename draft. An unchanged or empty name just closes the field.
    func commitRename(in pane: HubFilesPane) {
        guard let url = pane.renamingURL else { return }
        let draft = pane.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pane.endRename()
        guard !draft.isEmpty, draft != url.lastPathComponent else { return }
        do {
            let renamed = try HubFileOperations.rename(url, to: draft)
            pane.selectWhenListed([renamed])
            pane.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRename(in pane: HubFilesPane) {
        pane.endRename()
    }

    /// The pane whose rename field is open, if any.
    var renamingPane: HubFilesPane? {
        selectedTab.visiblePanes.first { $0.renamingURL != nil }
    }

    /// Creates "untitled folder" in the active pane's folder, selects it, and starts renaming it.
    func makeNewFolder() {
        let pane = activePane
        guard !isSearching, let folder = pane.folderURL else { return }
        do {
            let url = try HubFileOperations.makeFolder(in: folder, baseName: String(localized: .hubFilesUntitledFolder))
            pane.beginRename(url, name: url.lastPathComponent)
            pane.selectWhenListed([url])
            pane.markFresh([url])
            pane.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Trash

    /// Moves the selected items to the Trash. The folder watcher removes them from the listing.
    func trashSelection() {
        let urls = actionableItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            do {
                _ = try await HubFileOperations.moveToTrash(urls)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Transfers

    /// The job the status bar shows: the first running or paused job.
    var currentTransfer: HubFilesTransferStatus? {
        if let override = previewOverrides.transfer { return override }
        let live = transfers.jobs.filter { $0.state == .running || $0.state == .paused }
        guard let job = live.first else { return nil }
        return HubFilesTransferStatus(job, queuedCount: live.count - 1)
    }

    /// The job that ended last, for the 2.2 s completion message.
    var finishedTransfer: HubFilesTransferStatus? {
        if let override = previewOverrides.finished { return override }
        return transfers.lastFinished.map { HubFilesTransferStatus($0, queuedCount: 0) }
    }

    func togglePause(_ jobID: UUID) {
        guard let job = transfers.jobs.first(where: { $0.id == jobID }) else { return }
        if job.state == .paused { transfers.resume(jobID) } else { transfers.pause(jobID) }
    }

    func cancelTransfer(_ jobID: UUID) {
        transfers.cancel(jobID)
    }

    /// Flashes the arrived items in every pane that shows the job's destination.
    func transferDidFinish() {
        guard let job = transfers.lastFinished, job.state == .finished else { return }
        let arrived = job.sources.map { job.destination.appending(path: $0.lastPathComponent, directoryHint: .notDirectory) }
        for tab in tabs {
            for pane in tab.panes where pane.folderURL.map({ HubFilesPath.same($0, job.destination) }) ?? false {
                pane.markFresh(arrived)
                pane.reload()
            }
        }
    }

    // MARK: Volumes

    /// Ejects a drive. Panes showing it fall back home once it unmounts.
    func eject(_ volume: HubVolumes.Volume) {
        Task { [weak self] in
            do {
                try await self?.volumes.eject(volume)
                self?.volumeDidUnmount(volume.url)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Sends every pane showing a folder on the unmounted volume back home.
    ///
    /// Called after an eject from the sidebar and for `NSWorkspace.didUnmountNotification` while
    /// the tab is visible. Hidden panes also fall back when they next load and find the folder gone.
    func volumeDidUnmount(_ volumeURL: URL) {
        guard FilePathCopy.path(of: volumeURL) != "/" else { return }
        var changed = false
        for tab in tabs {
            for pane in tab.panes {
                guard let folder = pane.folderURL, HubFilesPath.contains(volumeURL, folder) else { continue }
                pane.replaceLocation(with: .folder(home))
                changed = true
            }
        }
        if changed { persist() }
    }
}
