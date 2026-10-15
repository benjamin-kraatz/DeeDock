import AppKit
import SwiftUI

/// Lookout in the Files search: its status and results (or the preview overrides), the one selection that spans the
/// names and Lookout sections, opening hits, the "Weaker matches" fold, and the analytics of a search.
///
/// Selection invariant: at most one of `searchSelection` (names, which may be several) and `lookoutSelection` (one
/// hit) is non-empty. Every entry point here and in `clickSearchResult` clears the other side.
extension HubFilesModel {
    // MARK: State

    /// Lookout's status for the chip and the section.
    var lookoutStatus: LookoutStatus { previewOverrides.lookoutStatus ?? lookout.status }

    /// The status as the chip and the section show it: while onboarding's model download runs before setup is
    /// complete, they show the download (and its progress) instead of "Set up". Their actions still follow
    /// `lookoutStatus`, so a click resumes onboarding.
    var lookoutDisplayStatus: LookoutStatus {
        let status = lookoutStatus
        return status == .notSetUp && lookoutDownloadProgress != nil ? .waitingForModel : status
    }

    /// Where reading stands, for the status chip's wash and percentage (`LookoutEngine.progress`).
    var lookoutProgress: LookoutProgressDisplay? {
        previewOverrides.lookoutStatus == nil ? lookout.progress : previewOverrides.lookoutProgress
    }

    /// The status chip's click: onboarding before setup, Lookout's Settings section after.
    func openLookoutFromChip(using openWindow: OpenWindowAction) {
        if lookoutStatus == .notSetUp {
            onSetUpLookout()
        } else {
            openLookoutSettings(using: openWindow)
        }
    }

    /// Opens Settings at Lookout's section.
    func openLookoutSettings(using openWindow: OpenWindowAction) {
        onOpenLookoutSettings()
        openWindow.openDockSettings()
    }
    /// Where Lookout's search for the current query is.
    var lookoutPhase: LookoutSearch.Phase { previewOverrides.lookoutPhase ?? lookout.search.phase }
    /// Lookout's latest results for the current query.
    var lookoutResults: LookoutResultSet { previewOverrides.lookoutResults ?? lookout.search.results }

    /// True while Lookout is set up and on (whatever it's doing).
    var isLookoutActive: Bool {
        switch lookoutStatus {
        case .notSetUp, .off: false
        default: true
        }
    }

    /// Whether search results show a Lookout section: always, except after Lookout was set up and turned off.
    var showsLookoutSection: Bool { lookoutStatus != .off }

    /// Lookout's hits as listed: the strong ones, then the weaker ones while the fold is open. In a search with a
    /// picture, the hits of both groups (`visiblePictureHits`).
    var visibleLookoutHits: [LookoutHit] {
        if isPictureSearch { return visiblePictureHits }
        let results = lookoutResults
        return lookoutWeakExpanded ? results.all : results.strong
    }

    /// The selected Lookout hit, when it's still listed.
    var selectedLookoutHit: LookoutHit? {
        guard let path = lookoutSelection else { return nil }
        return visibleLookoutHits.first { $0.path == path }
    }

    /// Every selectable result in the order Up and Down walk them.
    var searchOrder: [HubFilesSearchResultID] {
        if isPictureSearch { return visiblePictureHits.map { .lookout($0.path) } }
        return HubFilesSearchOrder.flattened(names: searchResults.map(\.url), lookout: lookoutResults,
                                             weakExpanded: lookoutWeakExpanded)
    }

    /// Where a hit is, as its row and the preview show it: "Desktop › Holiday Sylt 2026", with the sidebar's
    /// localized names for Desktop, Documents and Downloads.
    func lookoutLocation(of hit: LookoutHit) -> String {
        let home = home
        return LookoutLocation.text(forParentOf: hit.path, home: FilePathCopy.path(of: home)) { path in
            HubFilesPlace.place(for: URL(filePath: path, directoryHint: .isDirectory), home: home)?.title(home: home)
        }
    }

    /// The scope as analytics reports it.
    var analyticsSearchScope: AnalyticsHubSearchScope { searchScope == .thisMac ? .thisMac : .folder }

    // MARK: Selection

    /// Moves the selection `delta` results through both sections (`searchOrder`). Within the names, Shift extends
    /// the range as before; a Lookout hit is always selected alone.
    func moveSearchSelection(by delta: Int, extending: Bool) {
        let current: HubFilesSearchResultID? = lookoutSelection.map(HubFilesSearchResultID.lookout)
            ?? searchSelection.cursor.map(HubFilesSearchResultID.name)
        guard let target = HubFilesSearchOrder.step(from: current, by: delta, in: searchOrder) else { return }
        switch target {
        case .name(let url):
            if lookoutSelection == nil {
                // The names come first in `searchOrder`, so the same step within them lands on `url`, and
                // `HubFilesSelection` keeps Shift's range around its anchor.
                searchSelection.move(by: delta, order: searchResults.map(\.url), extending: extending)
            } else {
                lookoutSelection = nil
                searchSelection.set([url])
            }
        case .lookout(let path):
            searchSelection.clear()
            lookoutSelection = path
        }
        requestSearchScroll(to: target)
        quickLook.selectionDidChange()
    }

    /// A click on a Lookout row: selects that hit alone.
    func clickLookoutResult(_ hit: LookoutHit) {
        searchSelection.clear()
        lookoutSelection = hit.path
        quickLook.selectionDidChange()
    }

    private func requestSearchScroll(to id: HubFilesSearchResultID) {
        searchSerial += 1
        searchScrollRequest = HubFilesSearchScrollRequest(id: id, serial: searchSerial)
    }

    // MARK: Fold

    /// Opens or closes "Weaker matches". Closing it while a weaker hit is selected moves the selection to the last
    /// strong hit, the row just above the fold.
    func setLookoutWeakExpanded(_ expanded: Bool) {
        guard expanded != lookoutWeakExpanded else { return }
        lookoutWeakExpanded = expanded
        if expanded {
            Analytics.count(.lookoutWeakMatchesExpanded)
        } else if let path = lookoutSelection, lookoutResults.weak.contains(where: { $0.path == path }) {
            lookoutSelection = lookoutResults.strong.last?.path
            if let path = lookoutSelection { requestSearchScroll(to: .lookout(path)) }
            quickLook.selectionDidChange()
        }
    }

    // MARK: Open

    /// Opens a Lookout hit: a folder shows in the active pane and ends the search, as a folder name result does; a
    /// file opens in its app and an anchored Hub closes.
    func openLookoutResult(_ hit: LookoutHit) {
        let results = lookoutResults
        if isPictureSearch {
            trackPictureResultOpened(hit)
        } else if let index = results.strong.firstIndex(where: { $0.path == hit.path }) {
            Analytics.track(LookoutAnalytics.opened(hit, section: .strong, rank: index + 1, scope: analyticsSearchScope,
                                                    isLookup: results.isLookup))
        } else if let index = results.weak.firstIndex(where: { $0.path == hit.path }) {
            Analytics.track(LookoutAnalytics.opened(hit, section: .weak, rank: index + 1, scope: analyticsSearchScope,
                                                    isLookup: results.isLookup))
        }
        endLookoutSearchSession()
        let url = hit.fileItem.url
        if hit.isFolder {
            show(.folder(normalizing: url))
        } else {
            HubFileOperations.open([url])
            shell?.dismissAfterAction()
        }
    }

    /// Return with nothing selected: opens the first result, a name or else Lookout's best hit.
    func openFirstSearchResult() {
        switch searchOrder.first {
        case .name(let url)?:
            if let item = searchResults.first(where: { $0.url == url }) { openSearchResult(item) }
        case .lookout(let path)?:
            if let hit = visibleLookoutHits.first(where: { $0.path == path }) { openLookoutResult(hit) }
        case nil:
            break
        }
    }

    /// `lookout_result_opened` for a name result, while Lookout is on, so opens of names and of Lookout's hits
    /// compare. Called by `openSearchResult`.
    func trackNameResultOpenedForLookout(_ item: HubFileItem) {
        guard isLookoutActive, let index = searchResults.firstIndex(where: { $0.url == item.url }) else { return }
        Analytics.track(LookoutAnalytics.openedName(rank: index + 1, scope: analyticsSearchScope,
                                                    isLookup: lookoutResults.isLookup))
    }

    // MARK: Analytics

    /// Counts the search that ends now (the query was cleared, a result opened, or the tab hid) by what Lookout
    /// showed last: hits or the honest empty state. Once per search; nothing when Lookout is off or its final
    /// results hadn't arrived. Callers run this before the query's results are cleared.
    func endLookoutSearchSession() {
        guard !lookoutSearchCounted, isLookoutActive,
              let counter = LookoutAnalytics.searchCounter(phase: lookoutPhase, results: lookoutResults) else { return }
        lookoutSearchCounted = true
        Analytics.count(counter)
    }
}
