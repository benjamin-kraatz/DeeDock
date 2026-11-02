import Foundation

/// Decides whether a labelling prompt may appear now and about which app. Pure: the clock, the persisted
/// history, the person's choices, and the random draw are all passed in.
///
/// Caps: one visible question at a time, at most `promptsPerHour` per rolling hour, at most one prompt per app per
/// `perAppInterval`, never about DOKK itself or an app on the "Don't ask" list, and nothing while labelling is
/// paused. A suspicious candidate always wins over an ordinary one. An ordinary prompt keeps ordinary prompts near
/// a quarter of the remembered ones and is then picked with probability 1/3. Manual labels never come here.
nonisolated enum AppHealthPromptPolicy {
    static let promptsPerHour = 8
    static let rollingWindow: TimeInterval = 60 * 60
    static let perAppInterval: TimeInterval = 20 * 60
    /// Target share of ordinary prompts among the remembered rule and ordinary prompts.
    static let ordinaryShare = 0.25
    /// Chance that an eligible ordinary candidate is asked about in a tick.
    static let ordinaryProbability = 1.0 / 3
    /// How many shown prompts' triggers the ordinary share looks back over.
    static let rememberedTriggers = 100

    /// Everything outside the persisted history that a decision depends on.
    struct Context: Sendable {
        var now: Date
        /// A prompt or the manual picker is open.
        var questionVisible: Bool
        /// The end of "Pause labelling for today", if set.
        var pausedUntil: Date?
        var dontAsk: Set<String>
        /// DOKK's own bundle identifier: never asked about.
        var ownBundleID: String?
    }

    /// The gates that apply to every app: nothing visible, not paused, under the hourly cap. Checked before the
    /// rule runs, so a capped tick costs nothing.
    static func allowsAnyPrompt(history: AppHealthPromptHistory, context: Context) -> Bool {
        guard !context.questionVisible else { return false }
        if let pausedUntil = context.pausedUntil, context.now < pausedUntil { return false }
        let recent = history.shownAt.filter { isWithin(rollingWindow, of: context.now, $0) }.count
        return recent < promptsPerHour
    }

    /// The per-app gates: not DOKK, not on the "Don't ask" list, not asked about within `perAppInterval`.
    static func allowsAsking(about app: String, history: AppHealthPromptHistory, context: Context) -> Bool {
        guard app != context.ownBundleID, !context.dontAsk.contains(app) else { return false }
        guard let last = history.lastShown[app] else { return true }
        return !isWithin(perAppInterval, of: context.now, last)
    }

    /// Whether another ordinary prompt keeps the ordinary share under `ordinaryShare`:
    /// `ordinary < 0.25 × (rule + ordinary + 1)` over the remembered triggers.
    static func ordinaryShareAllows(_ triggers: [AppHealthPromptTrigger]) -> Bool {
        let recent = triggers.suffix(rememberedTriggers)
        let rule = recent.filter { $0 == .rule }.count
        let ordinary = recent.filter { $0 == .ordinary }.count
        return Double(ordinary) < ordinaryShare * Double(rule + ordinary + 1)
    }

    /// Picks the candidate to ask about this tick, or nil.
    ///
    /// - Parameter draw: Returns a number in `0..<1`. Called only when an ordinary candidate is eligible and no
    ///   suspicious one is, so tests can count draws.
    static func choose(from candidates: [AppHealthPromptCandidate], history: AppHealthPromptHistory,
                       context: Context, draw: () -> Double) -> AppHealthPromptCandidate? {
        guard allowsAnyPrompt(history: history, context: context) else { return nil }
        let eligible = candidates.filter { allowsAsking(about: $0.app, history: history, context: context) }
        if let rule = eligible.filter({ $0.trigger == .rule }).sorted(by: isMoreSuspicious).first {
            return rule
        }
        guard ordinaryShareAllows(history.triggers),
              let ordinary = eligible.filter({ $0.trigger == .ordinary }).sorted(by: isBusier).first
        else { return nil }
        return draw() < ordinaryProbability ? ordinary : nil
    }

    /// More flags first, then higher CPU, then bundle identifier, so the choice is deterministic.
    private static func isMoreSuspicious(_ lhs: AppHealthPromptCandidate, _ rhs: AppHealthPromptCandidate) -> Bool {
        if lhs.reasons.count != rhs.reasons.count { return lhs.reasons.count > rhs.reasons.count }
        return isBusier(lhs, rhs)
    }

    private static func isBusier(_ lhs: AppHealthPromptCandidate, _ rhs: AppHealthPromptCandidate) -> Bool {
        let left = lhs.evidence.meanCPUPercent ?? 0, right = rhs.evidence.meanCPUPercent ?? 0
        return left != right ? left > right : lhs.app < rhs.app
    }

    /// Whether `date` lies in the `length` seconds up to and including `now`. A date after `now` (the clock was set
    /// back) does not count.
    static func isWithin(_ length: TimeInterval, of now: Date, _ date: Date) -> Bool {
        date <= now && now.timeIntervalSince(date) < length
    }
}
