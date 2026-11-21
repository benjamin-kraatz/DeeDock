import Foundation

/// What Flix Pick knows about one candidate file or folder for one picker.
nonisolated struct FlixPickSignals: Equatable, Sendable {
    /// Times it was picked in this app's picker before (``FlixPickMemory``).
    var pickedCount = 0
    var lastPicked: Date?
    /// The Flix Thread it shares with this app's latest pick, by name.
    var threadName: String?
    /// Drops of its kind on this app (drag memory), with the kind (`FlixDragMemory.kindClass`).
    var dragCount = 0
    var dragKind: String?
    /// Its latest activity and when.
    var activity: FlixActivity?
    var date: Date
    /// Save pickers: recent files in the folder that fit the app.
    var fittingFiles = 0
}

/// The signal that contributed most to a candidate's score: what its reason line says.
nonisolated enum FlixPickSignal: Equatable, Sendable {
    case picked(Int)
    case thread(String)
    /// Downloaded or created in the last two days.
    case new
    case dragged(kind: String)
    case fittingFiles(Int)
    case used(FlixActivity)
    /// Nothing stood out: it fits the app and is recent enough to be listed.
    case fits
}

/// A candidate's score and its strongest signal.
nonisolated struct FlixPickScore: Equatable, Sendable {
    var total: Double
    var strongest: FlixPickSignal
}

/// Flix Pick's ranking: a sum of a few decaying signals, with the largest one named as the reason.
///
/// What the person actually picked in this app before weighs most, and keeps weighing for weeks;
/// a shared Thread with the last pick and a fresh download come next; drag memory and plain recency
/// follow. Type fit is a filter applied before scoring (``FlixPickDocumentTypes``), not a signal.
/// The weights are first guesses, chosen so that two picks a few days old outrank a file opened a
/// minute ago. Pure, so it can be tested without a picker.
nonisolated enum FlixPickRanker {
    /// The most rows the panel shows.
    static let limit = 5

    static func score(_ signals: FlixPickSignals, now: Date) -> FlixPickScore {
        let ageHours = max(0, now.timeIntervalSince(signals.date) / 3_600)
        var parts: [(FlixPickSignal, Double)] = []
        if signals.pickedCount > 0 {
            let pickDays = max(0, now.timeIntervalSince(signals.lastPicked ?? signals.date) / 86_400)
            parts.append((.picked(signals.pickedCount),
                          30 + 10 * Double(min(signals.pickedCount, 6)) + 10 * exp(-pickDays / 14)))
        }
        if let thread = signals.threadName { parts.append((.thread(thread), 22)) }
        if signals.activity == .downloaded || signals.activity == .created, ageHours < 48 {
            parts.append((.new, 14 + 8 * exp(-ageHours / 12)))
        }
        if signals.dragCount > 0, let kind = signals.dragKind {
            parts.append((.dragged(kind: kind), 8 + 2 * Double(min(signals.dragCount, 5))))
        }
        if signals.fittingFiles > 0 {
            parts.append((.fittingFiles(signals.fittingFiles), 10 + 4 * Double(min(signals.fittingFiles, 5))))
        }
        let recency = 20 * exp(-ageHours / 72)
        if let activity = signals.activity { parts.append((.used(activity), recency)) }
        let total = parts.reduce(0) { $0 + $1.1 } + (signals.activity == nil ? recency : 0)
        // A faint recency alone says little; "fits" is the honest reason then.
        let strongest = parts.max { $0.1 < $1.1 }.flatMap { $0.1 >= 3 ? $0.0 : nil } ?? .fits
        return FlixPickScore(total: total, strongest: strongest)
    }

    /// The best ``limit`` candidates, highest score first; ties keep the input order (newest first).
    static func rank<ID>(_ candidates: [(id: ID, signals: FlixPickSignals)], now: Date,
                         limit: Int = limit) -> [(id: ID, score: FlixPickScore)] {
        candidates.enumerated()
            .map { (offset: $0.offset, id: $0.element.id, score: score($0.element.signals, now: now)) }
            .sorted { $0.score.total != $1.score.total ? $0.score.total > $1.score.total : $0.offset < $1.offset }
            .prefix(limit)
            .map { (id: $0.id, score: $0.score) }
    }
}
