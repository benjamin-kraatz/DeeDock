import Foundation

/// Admission thresholds for a hearing. Changing these values never changes saved pins.
nonisolated struct PinJuryTuning: Equatable, Sendable {
    let minimumChallengerActivations: Int
    let minimumChallengerActiveDays: Int
    let minimumChallengerRecentActivations: Int
    let minimumScoreAdvantage: Int

    /// Clamps thresholds to the evidence limits and always requires a positive score advantage.
    init(minimumChallengerActivations: Int = 6, minimumChallengerActiveDays: Int = 3,
         minimumChallengerRecentActivations: Int = 3, minimumScoreAdvantage: Int = 3) {
        self.minimumChallengerActivations = min(PinJuryPolicy.maximumActivations, max(1, minimumChallengerActivations))
        self.minimumChallengerActiveDays = min(PinJuryPolicy.maximumActiveDays, max(1, minimumChallengerActiveDays))
        self.minimumChallengerRecentActivations = min(PinJuryPolicy.maximumActivations, max(1, minimumChallengerRecentActivations))
        self.minimumScoreAdvantage = min(PinJuryPolicy.maximumScore, max(1, minimumScoreAdvantage))
    }
}

/// Builds one evidence-qualified case. Foundation Models supplies the deliberation and votes;
/// this policy only limits which applications may be considered and never applies a pin edit.
nonisolated enum PinJuryPolicy {
    /// Matches the retained stable-activation cap in App suggestions.
    static let maximumActivations = 10_000
    /// A rolling 30-day interval can intersect 31 distinct local calendar dates.
    static let maximumActiveDays = 31
    static let maximumScore = maximumActivations * 3 + maximumActiveDays * 2

    /// Returns the weakest observed pin and strongest sufficiently supported challenger.
    /// The caller supplies available apps from the crowded display and excludes DDock itself.
    /// Finder is protected here. Pins without an observed activation are protected because
    /// missing history does not establish that a deliberately pinned application is unimportant.
    /// Score ties are resolved by stable application ID, independently of input ordering.
    static func makeCase(pins: [ApplicationReference], challengers: [ApplicationReference],
                         evidence: [String: PinJuryEvidence], now: Date = Date(),
                         tuning: PinJuryTuning = PinJuryTuning()) -> PinJuryCase? {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let pinnedIDs = Set(pins.map(\.id))
        let incumbents = candidates(pins, evidence: evidence).filter { $0.evidence.activations >= 1 }
        let eligibleChallengers = candidates(challengers, evidence: evidence).filter {
            !pinnedIDs.contains($0.id)
                && $0.evidence.activations >= tuning.minimumChallengerActivations
                && $0.evidence.activeDays >= tuning.minimumChallengerActiveDays
                && $0.evidence.recentActivations >= tuning.minimumChallengerRecentActivations
        }
        let incumbent = incumbents.sorted {
            let left = score($0.evidence), right = score($1.evidence)
            return left == right ? $0.id < $1.id : left < right
        }.first
        let challenger = eligibleChallengers.sorted {
            let left = score($0.evidence), right = score($1.evidence)
            return left == right ? $0.id < $1.id : left > right
        }.first
        guard let incumbent, let challenger,
              score(challenger.evidence) - score(incumbent.evidence) >= tuning.minimumScoreAdvantage else { return nil }
        return PinJuryCase(incumbent: incumbent, challenger: challenger, createdAt: now)
    }

    /// Activations over 30 days, plus twice the activations over seven days and active dates.
    /// Caps prevent malformed injected evidence from overflowing arithmetic or model prompts.
    static func score(_ evidence: PinJuryEvidence) -> Int {
        let evidence = bounded(evidence)
        return evidence.activations + 2 * evidence.recentActivations + 2 * evidence.activeDays
    }

    private static func candidates(_ applications: [ApplicationReference], evidence: [String: PinJuryEvidence]) -> [PinJuryCandidate] {
        var seen = Set<String>()
        return applications.compactMap { application in
            guard !application.id.isEmpty, application.id != "com.apple.finder",
                  seen.insert(application.id).inserted, let values = evidence[application.id] else { return nil }
            return PinJuryCandidate(application: application, evidence: bounded(values))
        }
    }

    private static func bounded(_ evidence: PinJuryEvidence) -> PinJuryEvidence {
        let activations = min(maximumActivations, max(0, evidence.activations))
        return PinJuryEvidence(activations: activations,
            recentActivations: min(activations, max(0, evidence.recentActivations)),
            activeDays: min(activations, min(maximumActiveDays, max(0, evidence.activeDays))),
            daysSinceUse: evidence.daysSinceUse.map { min(30, max(0, $0)) })
    }
}
