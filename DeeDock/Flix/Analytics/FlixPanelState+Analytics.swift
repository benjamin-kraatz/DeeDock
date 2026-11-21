import Foundation

/// Where an acted-on row sits, and the small analytics hooks the panel's commands call.
///
/// Places are read when the action happens, because the list moves on right after (a removed row,
/// a search that ends). Nothing here keeps a name or text: only sections, ranks, and counts.
extension FlixPanelState {
    /// The section and 1-based rank of `id` for an action from `origin` (nil: where the selection was
    /// made). Nil when the item is not on screen in that place.
    func analyticsPlace(of id: FlixItem.ID, origin: FlixActionOrigin?) -> (section: AnalyticsFlixSection, rank: Int?)? {
        switch origin ?? selectionOrigin {
        case .fits:
            guard let index = fitItems.firstIndex(where: { $0.1.id == id }) else { break }
            return (.fits, index + 1)
        case .threadCard:
            return (.thread, nil)
        case .morningCard:
            return (.morningCard, nil)
        case .list:
            break
        }
        let section: AnalyticsFlixSection = if intelligence.moreLikeThis != nil { .moreLikeThis }
            else if searchActive { .search }
            else { filter.analyticsSection }
        return (section, list.order.firstIndex(of: id).map { $0 + 1 })
    }

    /// How a search result matched, for `chosen_match`.
    func searchMatch(of id: FlixItem.ID) -> AnalyticsFlixMatch? {
        for section in list.sections {
            guard let row = section.rows.first(where: { $0.item.id == id }) else { continue }
            switch row.match {
            case .meaning: return .meaning
            case .name: return .name
            case nil: return nil
            }
        }
        return nil
    }

    /// The search list as it was for `text`, for a search that ends after the field was emptied.
    func searchResults(for text: String) -> FlixListResult {
        var input = listInput
        input.searchText = text
        input.searchActive = true
        input.moreLikeThis = nil
        return FlixListBuilder.build(input)
    }

    /// Counts an action on the visit, and on the place it came from.
    func reportAction(_ action: FlixSessionAction, _ items: [FlixItem], origin: FlixActionOrigin?) {
        metrics?.acted(action, items: items, origin: origin)
    }

    /// A Thread chosen in the sidebar (or by Show Thread) reports `flix_thread_used` with `filter`.
    func reportThreadFilter() {
        guard case .thread(let id) = filter, let thread = intelligence.thread(id) else { return }
        reportThread(.filter, thread)
    }

    func reportThread(_ action: AnalyticsFlixThreadAction, _ thread: FlixThread) {
        guard metrics?.isOpen == true else { return }
        Analytics.track(.flixThreadUsed(action, threadSize: thread.memberIDs.count,
                                        namedBy: thread.namedByAppleIntelligence ? .appleIntelligence : .folder))
    }

    // MARK: Tidy

    /// Sends a waiting Tidy apply once its Undo window passed or Undo was pressed.
    func settleTidy(undone: Bool) {
        guard var tidy = pendingTidy else { return }
        pendingTidy = nil
        tidy.undone = undone
        Analytics.track(.flixTidy(tidy))
    }

    /// The Tidy sheet closed without applying.
    func reportTidyDismissed() {
        let shown = intelligence.tidy.filter { history.item($0.itemID) != nil }
        guard !shown.isEmpty else { return }
        Analytics.track(.flixTidy(AnalyticsFlixTidy(shownMoves: shown.count { $0.moveTo != nil },
                                                    shownRenames: shown.count { $0.rename != nil })))
    }

    // MARK: Smart Filters

    func reportSmartFilterCreated(_ filter: FlixSmartFilter, generator: AnalyticsFlixGenerator?) {
        let semantic: (String, FlixItem) -> Bool? = { [intelligence] topic, item in
            intelligence.semanticMatch(topic: topic, item: item)
        }
        let matches = history.items.count { filter.matches($0, now: now, semantic: semantic) }
        var kinds: [AnalyticsFlixRuleKind] = []
        for kind in filter.rules.map(\.analyticsRuleKind) where !kinds.contains(kind) { kinds.append(kind) }
        Analytics.track(.flixSmartFilterCreated(source: filter.origin?.analytics ?? .manual, ruleKinds: kinds,
                                                matchCount: matches, generator: generator))
    }
}

extension FlixSmartFilterOrigin {
    var analytics: AnalyticsFlixFilterSource {
        switch self {
        case .sentence: .sentence
        case .tip: .tip
        case .manual: .manual
        }
    }
}

// MARK: - Drops inside the panel and kept links

extension FlixPanelState {
    /// Rows dropped on a sidebar favorite: a folder moves them, an app opens them.
    func reportFavoriteDrop(_ items: [FlixItem], on favorite: FlixFavorite) {
        let origin = dragOrigin ?? .list
        let place = items.first.flatMap { analyticsPlace(of: $0.id, origin: origin) }
        metrics?.acted(.drag, items: items, origin: origin)
        let category: FlixAppCategory? = favorite.kind == .app
            ? FlixAppCategory.of(bundleIdentifier: Bundle(url: favorite.url)?.bundleIdentifier, bundleURL: favorite.url)
            : nil
        let target: AnalyticsFlixDropTarget = favorite.kind == .app ? .favoriteApp : .favoriteFolder
        Analytics.track(.flixDrop(AnalyticsFlixDrop(
            items: items, source: origin == .fits ? .fits : origin == .threadCard ? .threadCard : .row, place: place,
            target: target, targetCategory: category, pageKind: nil, plan: nil, warning: .none, resolution: nil,
            pinned: isPinned, predicted: false)))
    }

    /// A web address dropped on the panel was kept: a deliberate save.
    func reportLinkKept(_ link: FlixLink, removedSecrets: Int) {
        Analytics.count(.linksRecorded)
        Analytics.count(.linkTokensStripped, by: removedSecrets)
        guard !history.items.contains(where: { $0.link?.url == link.url }) else { return }
        Analytics.track(.flixLinkSaved(.savedDrag, pageKind: AnalyticsFlixPageKind(url: link.url)))
    }
}

// MARK: - Drop questions

/// A drop question that was answered, so the drag that follows reports it.
struct FlixAnsweredWarning: Equatable {
    var itemIDs: Set<FlixItem.ID>
    var warning: AnalyticsFlixWarning
    var resolution: AnalyticsFlixWarningResolution
}

extension FlixDropConfirmation {
    var analyticsWarning: AnalyticsFlixWarning {
        switch self {
        case .sensitive: .sensitive
        case .newerVersion: .olderVersion
        }
    }
}

extension FlixPanelState {
    /// The drag source a drop report names for the drag that started from ``dragOrigin``.
    var dragSource: AnalyticsFlixDropSource {
        if dragFromTile { return .tile }
        switch dragOrigin {
        case .fits: return .fits
        case .threadCard: return .threadCard
        case .list, .morningCard, nil: return .row
        }
    }

    /// Answers the question on screen: lets the next drag of `ids` go ahead and remembers the answer
    /// for its drop report. Cancelling is closing the question (``confirmation`` = nil).
    func resolveConfirmation(_ resolution: AnalyticsFlixWarningResolution, ids: [FlixItem.ID]) {
        guard let pending = confirmation else { return }
        answeredWarning = FlixAnsweredWarning(itemIDs: Set(ids), warning: pending.confirmation.analyticsWarning,
                                              resolution: resolution)
        confirmationAnswered = true
        confirmation = nil
        confirmDrag?(ids)
    }

    /// The answer that applies to a drag of `ids`, consumed by the drag.
    func takeAnsweredWarning(for ids: [FlixItem.ID]) -> FlixAnsweredWarning? {
        guard let answered = answeredWarning, Set(ids).isSubset(of: answered.itemIDs) else { return nil }
        answeredWarning = nil
        return answered
    }

    /// A drag stopped at a question that was closed without an answer.
    func reportWarningCancelled(_ pending: FlixPendingConfirmation) {
        let items = pending.itemIDs.compactMap(history.item)
        guard !items.isEmpty else { return }
        let place = dragFromTile ? nil : items.first.flatMap { analyticsPlace(of: $0.id, origin: dragOrigin ?? .list) }
        Analytics.track(.flixDrop(AnalyticsFlixDrop(
            items: items, source: dragSource, place: place, target: nil, targetCategory: nil, pageKind: nil, plan: nil,
            warning: pending.confirmation.analyticsWarning, resolution: .cancel, pinned: isPinned,
            predicted: intelligence.likelyItem(for: frontmost, among: history.items).map(pending.itemIDs.contains) ?? false)))
    }
}
