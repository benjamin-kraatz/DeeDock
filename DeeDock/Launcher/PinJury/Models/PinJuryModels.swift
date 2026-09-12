import Foundation

/// The three perspectives in a hearing, ordered consistently for both rounds.
nonisolated enum PinJuror: String, CaseIterable, Identifiable, Sendable {
    case keeper
    case scout
    case steward

    var id: String { rawValue }
}

/// A ballot about the existing pin. It has no authority to modify the dock.
nonisolated enum PinJuryVote: String, Equatable, Sendable {
    case keep
    case replace
}

/// A snapshot of settled app activations from the existing local, opt-in history.
nonisolated struct PinJuryEvidence: Sendable, Equatable {
    /// Observed activations in the last 30 days, without an inference about time spent.
    let activations: Int
    /// The subset of activations observed in the last seven days.
    let recentActivations: Int
    /// Distinct calendar days with an observed activation in the last 30 days.
    let activeDays: Int
    /// Calendar days since the latest observed activation, or nil when none occurred in 30 days.
    let daysSinceUse: Int?
}

/// A fixed application identity and the evidence the person can review before a hearing.
nonisolated struct PinJuryCandidate: Sendable, Equatable, Identifiable {
    let application: ApplicationReference
    let evidence: PinJuryEvidence

    var id: String { application.id }
}

/// The pair being considered. A hearing never expands its choices beyond these applications.
nonisolated struct PinJuryCase: Sendable, Equatable {
    let incumbent: PinJuryCandidate
    let challenger: PinJuryCandidate
    let createdAt: Date
}

/// One streaming statement. Only a complete statement can supply a ballot to the final tally.
nonisolated struct PinJuryTurn: Identifiable, Sendable, Equatable {
    /// Stable across streaming updates, formatted as the juror's raw value followed by the round.
    let id: String
    let juror: PinJuror
    /// One is the opening argument; two is the response and final ballot.
    let round: Int
    let text: String
    let vote: PinJuryVote?
    let isComplete: Bool
}

/// Generates a hearing without access to pin persistence, application launching, or other tools.
nonisolated protocol PinJuryGenerating: Sendable {
    /// Streams six turns in order and returns only after all have passed validation.
    ///
    /// The caller owns cancellation and must discard any verdict when this method throws,
    /// even if earlier turns completed. Updates are awaited to preserve transcript order.
    func deliberate(
        _ juryCase: PinJuryCase,
        localeIdentifier: String,
        update: @escaping @Sendable (PinJuryTurn) async -> Void
    ) async throws
}

/// Failure categories translated by the presentation layer, without exposing model diagnostics.
nonisolated enum PinJuryFailure: Error, Equatable, Sendable {
    case deviceNotEligible
    case intelligenceDisabled
    case modelNotReady
    case unsupported
    case invalidOutput
    case contextLimit
    case refused
    case failed
}
