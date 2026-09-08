import Foundation

/// Shared evidence requirements. Defaults are experimental starting points, not accuracy claims.
/// Runtime overrides are exposed and persisted only in Debug builds.
nonisolated struct LauncherSuggestionTuning: Codable, Equatable, Sendable {
    var minHistory = 30
    var minSupport = 3
    var minDays = 2
    var minAgreement = 0.6
    /// Squared Euclidean distance in the model's existing feature representation.
    var maxDistance = 2.0
    var neighbors = 15

    var clamped: Self {
        var value = self
        value.minHistory = min(1_000, max(0, minHistory))
        value.minSupport = min(100, max(0, minSupport))
        value.minDays = min(30, max(0, minDays))
        value.minAgreement = minAgreement.isFinite ? min(1, max(0, minAgreement)) : Self().minAgreement
        value.maxDistance = maxDistance.isFinite ? min(20, max(0, maxDistance)) : Self().maxDistance
        value.neighbors = min(100, max(1, neighbors))
        return value
    }
}

/// A failed gate explains abstention independently of the engine's ranking score.
nonisolated enum LauncherSuggestionGateReason: String, CaseIterable, Sendable {
    case history, support, days, agreement, distance, excluded, foreground, nonPositive, unavailable
}

/// Reconstructed nearest example, not an internal neighbor record exported by Core ML.
nonisolated struct LauncherSuggestionNeighbor: Identifiable, Sendable {
    let id: UUID
    let appID: String
    let date: Date
    let distance: Double
    let context: LauncherSuggestionContext
}

/// Numeric evidence is kept separate from presentation copy and from calibrated probability.
nonisolated struct LauncherSuggestionCandidateEvidence: Identifiable, Sendable {
    let id: String
    let rawScore: Double
    let ageFactor: Double
    let normalizedScore: Double
    let recencyBonus: Double
    let runningBonus: Double
    let feedbackAdjustment: Double
    let finalScore: Double
    let support: Int
    let distinctDays: Int
    let agreement: Double
    let nearestDistance: Double?
    let reasons: [LauncherSuggestionGateReason]
    var eligible: Bool { reasons.isEmpty }
}

/// One engine evaluated against a captured input and immutable tuning settings.
nonisolated struct LauncherSuggestionEvaluation: Sendable {
    let engine: LauncherSuggestionEngine
    let candidates: [LauncherSuggestionCandidateEvidence]
    let neighbors: [LauncherSuggestionNeighbor]
    var elapsedMilliseconds: Double
    var preparationMilliseconds: Double? = nil
    var inferenceMilliseconds: Double? = nil
    var cacheReused: Bool? = nil
    var effectiveNeighbors: Int? = nil
    var rankedIDs: [String] { candidates.filter(\.eligible).map(\.id) }
}
