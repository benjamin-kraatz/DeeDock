import AppKit

/// Collects one panel visit for `flix_session_ended`, and the shorter visits inside it that report
/// when they end: a search (`flix_search_ended`), More like this (`flix_more_like_this`), and an
/// unanswered morning card (`flix_morning_card` with `ignored`).
///
/// Ownership: one per `FlixCoordinator`, which calls ``begin(trigger:placement:displayBuiltin:front:unseen:listSize:)``
/// right after the panel state was reset for an open and ``end(reason:pinned:)`` first thing when it
/// closes, so exactly one session event leaves per open. Between the two, `FlixPanelState`,
/// `FlixIntelligence`, and the coordinator report actions here; every call outside a visit is ignored,
/// so the resets an open performs never count. Sections and ranks are read from the panel state at
/// the moment of the action, which is when the row's place is known. Main actor; nothing here
/// waits, reads files, or holds text: the search sentence is reduced to a word count when it ends.
@MainActor
final class FlixSessionMetrics {
    /// The open visit, nil while the panel is closed.
    private(set) var record: FlixSessionRecord?
    /// Where events go. Tests replace it.
    var send: (AnalyticsEvent) -> Void = { Analytics.track($0) }
    var now: () -> Date = { .now }
    /// The panel the visit happens in, for sections, ranks, and the search's results.
    weak var panel: FlixPanelState?

    private struct SearchVisit {
        var removed: [AnalyticsFlixQueryTokenType] = []
    }

    private struct LikeVisit {
        var sourceKind: AnalyticsFlixItemKind?
    }

    private var search: SearchVisit?
    private var like: LikeVisit?
    private var morningAnswered = false

    var isOpen: Bool { record != nil }

    // MARK: The visit

    /// Starts a visit. Called after the panel state was reset, so `listSize` is the list as drawn.
    func begin(trigger: AnalyticsFlixTrigger, placement: AnalyticsFlixPlacement, displayBuiltin: Bool,
               front: FlixAppCategory, unseen: Int, listSize: Int) {
        record = FlixSessionRecord(trigger: trigger, placement: placement, displayBuiltin: displayBuiltin,
                                   openedAt: now(), frontCategory: front, unseenAtOpen: unseen,
                                   listSizeAtOpen: listSize)
        search = nil
        like = nil
        lastSearchText = ""
        morningAnswered = false
    }

    /// Ends the visit and sends its events. Safe to call when no visit is open.
    func end(reason: FlixCloseReason, pinned: Bool) {
        guard let record else { return }
        endSearch(outcome: .none, chosen: nil)
        endMoreLikeThis(outcome: .none)
        if record.morningCardShown, !morningAnswered, let card = panel?.intelligence.morning {
            send(.flixMorningCard(.ignored, threadCount: Self.threadCount(card)))
        }
        send(.flixSessionEnded(record.session(endedAt: now(), closedBy: reason, pinned: pinned)))
        self.record = nil
    }

    // MARK: Actions

    /// Items were acted on. The first item's place in the panel becomes the first action's section and
    /// rank; a use from search or More like this also ends that visit with its outcome.
    func acted(_ action: FlixSessionAction, items: [FlixItem], origin: FlixActionOrigin?) {
        guard record != nil else { return }
        let place = items.first.flatMap { panel?.analyticsPlace(of: $0.id, origin: origin) }
        acted(action, items: items, at: place)
    }

    /// The same, with the place read earlier (a drag reads it when it starts, since the list can
    /// change before the drop).
    func acted(_ action: FlixSessionAction, items: [FlixItem], at place: (section: AnalyticsFlixSection, rank: Int?)?) {
        guard record != nil else { return }
        let first = items.first
        record?.record(action, item: first, place: place, at: now())
        guard let place, action == .open || action == .drag else { return }
        let outcome: AnalyticsFlixResultOutcome = action == .open ? .opened : .dragged
        if place.section == .search, let first {
            endSearch(outcome: outcome, chosen: (place.rank, panel?.searchMatch(of: first.id)))
        } else if place.section == .moreLikeThis {
            endMoreLikeThis(outcome: outcome)
        }
    }

    /// The pointer pressed something in the panel.
    func pointerPressed() { record?.keyboardOnly = false }

    func filterChanged(to filter: FlixFilter) { record?.filterChanged(to: filter) }

    func scrolled(rows: Int) { record?.scrolled(rows: rows) }

    // MARK: Fits

    /// The Fits section's reading finished (or was never possible).
    func fitsRead(reader: AnalyticsFlixReader, readyMs: Int?, shown: Int) {
        guard record != nil else { return }
        record?.fitsReader = reader
        record?.fitsReadyMs = readyMs
        record?.fitsShown = shown
    }

    // MARK: Morning card

    func morningShown() { record?.morningCardShown = true }

    func morningActed(_ action: AnalyticsFlixMorningAction, card: FlixMorningCard) {
        guard record != nil, !morningAnswered else { return }
        morningAnswered = true
        send(.flixMorningCard(action, threadCount: Self.threadCount(card)))
    }

    /// Threads the card offers to show, counting the primary "reopen" thread.
    static func threadCount(_ card: FlixMorningCard) -> Int {
        card.actions.count { action in
            if case .filter(.thread) = action.target { return true }
            return action.isPrimary
        }
    }

    // MARK: Search

    /// The search text changed. A first word starts a search visit; emptying the field ends it.
    func searchTextChanged(_ text: String) {
        guard record != nil else { return }
        let hasWords = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasWords {
            record?.searchUsed = true
            if search == nil { search = SearchVisit() }
            lastSearchText = text
        } else if search != nil {
            endSearch(outcome: .none, chosen: nil)
        }
    }

    /// The text the current search visit last had; the field may be empty by the time it ends.
    /// Only its word count is ever reported.
    private var lastSearchText = ""

    func searchTokenRemoved(_ type: AnalyticsFlixQueryTokenType) {
        search?.removed.append(type)
    }

    /// Search was closed (Escape, the field's ✕, a filter chosen).
    func searchClosed() {
        endSearch(outcome: .none, chosen: nil)
    }

    /// Sends the search visit, if one is open. Must run before the panel clears the understood query,
    /// which is why `FlixPanelState` reports text changes and closing before acting on them.
    private func endSearch(outcome: AnalyticsFlixResultOutcome, chosen: (rank: Int?, match: AnalyticsFlixMatch?)?) {
        guard let visit = search, let panel else { search = nil; return }
        search = nil
        let sentence = lastSearchText
        let words = FlixWords.words(sentence).count
        guard words > 0 else { return }
        let tokens: [FlixQueryToken]
        let matches: [FlixItem.ID: FlixMatchKind]?
        if case .understood(let understood, let found) = panel.intelligence.query {
            tokens = understood
            matches = found
        } else {
            tokens = []
            matches = nil
        }
        let report = panel.intelligence.searchReport
        let list = panel.searchResults(for: sentence)
        send(.flixSearchEnded(AnalyticsFlixSearch(
            queryWordCount: words, tokenCount: tokens.count, tokenTypes: tokens.map(\.rule.analyticsTokenType),
            tokensRemoved: visit.removed, parser: report?.parser, parseMs: report?.parseMs, resultCount: list.count,
            byMeaningCount: matches?.values.count { $0 == .meaning } ?? 0,
            lookoutAvailable: report?.lookoutAvailable ?? panel.intelligence.lookoutAvailable, outcome: outcome,
            chosenRank: chosen?.rank, chosenMatch: chosen?.match)))
    }

    // MARK: More like this

    /// More like this started, finished loading, or ended.
    func moreLikeThisChanged(from old: FlixMoreLikeThis?, to new: FlixMoreLikeThis?) {
        guard record != nil else { return }
        if let old, old.sourceID != new?.sourceID { endMoreLikeThis(outcome: .none, results: old.resultIDs?.count) }
        if let new, old?.sourceID != new.sourceID {
            like = LikeVisit(sourceKind: panel?.history.item(new.sourceID)?.analyticsKind)
        }
    }

    private func endMoreLikeThis(outcome: AnalyticsFlixResultOutcome, results: Int? = nil) {
        guard let visit = like else { return }
        like = nil
        let count = results ?? panel?.intelligence.moreLikeThis?.resultIDs?.count ?? 0
        send(.flixMoreLikeThis(resultCount: count, outcome: outcome, itemKind: visit.sourceKind))
    }
}
