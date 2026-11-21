import Foundation

/// Turns a window's demand and the history into at most three fits.
///
/// Order: each wanted phrase first gets its best item (in the window's order), then any slot left
/// goes to the next best scores. An item appears once. Items the window could not take are left
/// out: folders, apps, and links on an upload page, and files whose type the page refuses when no
/// conversion can make it acceptable (``FlixConversionPlanner``).
nonisolated enum FlixFitRanker {
    static let maximumFits = 3
    /// Below this a match is a coincidence: one keyword of three, say.
    static let minimumScore = 0.5
    /// Only the newest items are scored, which keeps a read under a few milliseconds.
    static let candidateLimit = 1_500

    struct Ranked: Equatable, Sendable {
        var itemID: FlixItem.ID
        var phrase: String
        var score: Double
    }

    /// What drag memory adds to the item it expects the window to want: enough to win a tie or a
    /// near-tie, never enough to make a non-match pass.
    static let preferredBonus = 0.04

    /// - Parameter preferred: Drag memory's guess (`likelyItem(for:among:)`), which wins ties.
    static func rank(demand: FlixWindowDemand, candidates: [FlixFitCandidate], scorer: any FlixFitScoring,
                     now: Date, preferred: FlixItem.ID? = nil) -> [Ranked] {
        let usable = candidates.prefix(candidateLimit).filter { isUsable($0.item, for: demand) }
        guard !demand.wanted.isEmpty, !usable.isEmpty else { return [] }
        var all: [Ranked] = []
        var best: [[Ranked]] = []
        for wanted in demand.wanted {
            let scored = usable.compactMap { candidate -> Ranked? in
                var score = scorer.score(wanted, item: candidate, now: now)
                guard score >= minimumScore else { return nil }
                if candidate.item.id == preferred { score += preferredBonus }
                return Ranked(itemID: candidate.item.id, phrase: wanted.phrase, score: score)
            }
            .sorted { $0.score > $1.score }
            best.append(scored)
            all.append(contentsOf: scored)
        }
        var result: [Ranked] = []
        var used = Set<FlixItem.ID>()
        for scored in best {
            guard result.count < maximumFits, let top = scored.first(where: { !used.contains($0.itemID) }) else { continue }
            result.append(top)
            used.insert(top.itemID)
        }
        for ranked in all.sorted(by: { $0.score > $1.score }) where result.count < maximumFits {
            guard !used.contains(ranked.itemID) else { continue }
            result.append(ranked)
            used.insert(ranked.itemID)
        }
        return result
    }

    static func isUsable(_ item: FlixItem, for demand: FlixWindowDemand) -> Bool {
        if demand.pageKind == .upload, item.kind == .folder || item.kind == .app || item.kind == .link { return false }
        guard item.kind != .app else { return false }
        if item.kind == .link { return demand.pageKind == .chat || demand.pageKind == .mail || demand.pageKind == .document }
        guard demand.hasLimits else { return true }
        return FlixConversionPlanner.decision(for: item, demand: demand) != .unconvertible
    }
}
