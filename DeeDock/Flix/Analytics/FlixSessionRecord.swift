import Foundation

/// Where in the panel an action on items came from, before it becomes an analytics section.
nonisolated enum FlixActionOrigin: Equatable, Sendable {
    /// A row of the list (the stream, a filter, a search, More like this).
    case list
    /// A row of the "✦ Fits" section.
    case fits
    /// A Thread's card.
    case threadCard
    /// The morning card's buttons.
    case morningCard
}

/// What was done to items during a visit.
nonisolated enum FlixSessionAction: Hashable, Sendable {
    case drag, open, reveal, copy, quickLook, flag, favorite, remove, trash, robi
    /// Anything else that touches items (move, rename, Shelf): it can be the first action but has
    /// no count of its own.
    case other
}

/// Why the panel closed, as far as the coordinator knows.
nonisolated enum FlixCloseReason: Equatable, Sendable {
    case escape
    /// A click outside the panel, another app coming forward, or the tile or menu bar item clicked again.
    case clickedAway
    /// The shortcut pressed again.
    case shortcutToggle
    /// A drop elsewhere, an open or reveal that hands over to another app, Settings, or Flix turned off.
    case other
}

/// The accumulator behind `flix_session_ended`: everything one panel visit did, in plain values.
///
/// `FlixSessionMetrics` creates one when the panel opens, feeds it as things happen, and turns it into
/// exactly one ``AnalyticsFlixSession`` when the panel closes. It is a value with no clock or
/// analytics dependency of its own, so the rules (what counts as the first action, which outcome
/// wins) are tested directly.
nonisolated struct FlixSessionRecord: Equatable, Sendable {
    let trigger: AnalyticsFlixTrigger
    let placement: AnalyticsFlixPlacement
    let displayBuiltin: Bool
    let openedAt: Date
    let frontCategory: FlixAppCategory
    let unseenAtOpen: Int
    let listSizeAtOpen: Int

    /// False once the pointer pressed anything in the panel.
    var keyboardOnly = true
    var drags = 0
    var opens = 0
    var reveals = 0
    var copies = 0
    var quickLooks = 0
    var flags = 0
    var favorites = 0
    var removes = 0
    var trashes = 0
    var robiQuestions = 0
    var firstAction: AnalyticsFlixSession.FirstAction?
    var firstActionAt: Date?
    var filterChanges = 0
    var sidebarAreas: Set<FlixSidebarArea> = []
    var maxScrolledRows = 0
    var searchUsed = false
    var fitsShown = 0
    var fitsReader: AnalyticsFlixReader?
    var fitsReadyMs: Int?
    var fitsAccepted = false
    var fitsRank: Int?
    var morningCardShown = false

    init(trigger: AnalyticsFlixTrigger, placement: AnalyticsFlixPlacement, displayBuiltin: Bool, openedAt: Date,
         frontCategory: FlixAppCategory, unseenAtOpen: Int, listSizeAtOpen: Int) {
        self.trigger = trigger
        self.placement = placement
        self.displayBuiltin = displayBuiltin
        self.openedAt = openedAt
        self.frontCategory = frontCategory
        self.unseenAtOpen = unseenAtOpen
        self.listSizeAtOpen = listSizeAtOpen
    }

    /// Counts one action and keeps it as the first action when it is the first.
    ///
    /// - Parameters:
    ///   - place: The section and 1-based rank the first item was acted on from; nil leaves the
    ///     first action without a section (it then waits for one that has one).
    ///   - item: The first item acted on, for its kind, event, and age.
    mutating func record(_ action: FlixSessionAction, item: FlixItem?,
                         place: (section: AnalyticsFlixSection, rank: Int?)?, at date: Date) {
        switch action {
        case .drag: drags += 1
        case .open: opens += 1
        case .reveal: reveals += 1
        case .copy: copies += 1
        case .quickLook: quickLooks += 1
        case .flag: flags += 1
        case .favorite: favorites += 1
        case .remove: removes += 1
        case .trash: trashes += 1
        case .robi: robiQuestions += 1
        case .other: break
        }
        // Using a suggestion accepts it; looking at it, flagging it, or removing it does not.
        if let place, place.section == .fits, !fitsAccepted, Self.acceptsFit.contains(action) {
            fitsAccepted = true
            fitsRank = place.rank
        }
        guard firstAction == nil, let place else { return }
        firstAction = AnalyticsFlixSession.FirstAction(section: place.section, rank: place.rank,
                                                       itemKind: item?.analyticsKind, itemEvent: item?.analyticsEvent,
                                                       itemAgeMinutes: item?.ageMinutes(now: date))
        firstActionAt = date
    }

    /// A sidebar filter was chosen.
    mutating func filterChanged(to filter: FlixFilter) {
        filterChanges += 1
        sidebarAreas.insert(filter.sidebarArea)
    }

    /// The list was scrolled so that `rows` rows are above the top edge.
    mutating func scrolled(rows: Int) {
        maxScrolledRows = max(maxScrolledRows, rows)
    }

    /// How the visit ended: the strongest action wins, then the way the panel closed.
    func outcome(closedBy reason: FlixCloseReason) -> AnalyticsFlixOutcome {
        if drags > 0 { return .draggedOut }
        if opens > 0 { return .opened }
        if reveals > 0 { return .revealed }
        if copies > 0 { return .copied }
        if robiQuestions > 0 { return .robi }
        if quickLooks > 0 { return .quickLookOnly }
        switch reason {
        case .escape: return .escape
        case .clickedAway: return .clickedAway
        case .shortcutToggle: return .shortcutToggle
        case .other: return .nothing
        }
    }

    /// The finished visit.
    func session(endedAt date: Date, closedBy reason: FlixCloseReason, pinned: Bool,
                 calendar: Calendar = .current) -> AnalyticsFlixSession {
        let components = calendar.dateComponents([.hour, .weekday], from: openedAt)
        // `Calendar` counts 1 = Sunday; ISO counts 1 = Monday … 7 = Sunday.
        let weekday = ((components.weekday ?? 1) + 5) % 7 + 1
        var session = AnalyticsFlixSession(
            trigger: trigger, placement: placement, displayBuiltin: displayBuiltin, keyboardOnly: keyboardOnly,
            localHour: components.hour ?? 0, weekday: weekday, durationMs: Self.milliseconds(from: openedAt, to: date),
            timeToFirstActionMs: firstActionAt.map { Self.milliseconds(from: openedAt, to: $0) },
            frontCategory: frontCategory, unseenAtOpen: unseenAtOpen, listSizeAtOpen: listSizeAtOpen,
            outcome: outcome(closedBy: reason))
        session.drags = drags
        session.opens = opens
        session.copies = copies
        session.quickLooks = quickLooks
        session.flags = flags
        session.favorites = favorites
        session.removes = removes
        session.trashes = trashes
        session.firstAction = firstAction
        session.filterChanges = filterChanges
        session.sidebarAreasUsed = sidebarAreas.count
        session.maxScrolledRows = maxScrolledRows
        session.searchUsed = searchUsed
        session.fitsShown = fitsShown
        session.fitsReader = fitsReader
        session.fitsReadyMs = fitsReadyMs
        session.fitsAccepted = fitsAccepted
        session.fitsRank = fitsRank
        session.morningCardShown = morningCardShown
        session.pinned = pinned
        return session
    }

    /// Actions that count as taking a "Fits" suggestion.
    static let acceptsFit: Set<FlixSessionAction> = [.drag, .open, .reveal, .copy]

    static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}
