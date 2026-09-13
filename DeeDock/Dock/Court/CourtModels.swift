import Foundation

/// Saved fiction, deliberately separate from observed app activity.
nonisolated struct CourtCharacter: Codable, Identifiable, Sendable {
    let id: String
    let appName: String
    let biography: String
    let counsel: String
    let counselBiography: String
    let opposingCounsel: String
    let opposingBiography: String
    let motive: String
    let incident: String
    let relatedAppID: String?
    let relationship: String
    var lastAppearance: Date?
}

nonisolated struct CourtCaseSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let appID: String
    let participantIDs: [String]
    let date: Date
    let summary: String
}

nonisolated struct CourtDocument: Codable {
    var version = 1
    var enabled = false
    var skippedForever = false
    var characters: [String: CourtCharacter] = [:]
    var cases: [CourtCaseSummary] = []
    var relationships: [String: String] = [:]
    var pinSince: [String: Date] = [:]
    var lastHearing: Date?
}

nonisolated enum CourtRole: String, Sendable {
    case separation, reconciliation, judge, witness
    var title: LocalizedStringResource {
        switch self {
        case .separation: .courtSeparation
        case .reconciliation: .courtReconciliation
        case .judge: .courtJudge
        case .witness: .courtWitness
        }
    }
    var symbol: String {
        switch self {
        case .separation: "briefcase.fill"
        case .reconciliation: "heart.text.clipboard.fill"
        case .judge: "building.columns.fill"
        case .witness: "eye.fill"
        }
    }
}

nonisolated struct CourtTurn: Identifiable, Sendable {
    let id = UUID()
    let role: CourtRole
    let phase: LocalizedStringResource
    let text: String
}

/// Only these aggregate counts may cross into a court prompt.
nonisolated struct CourtUsage: Codable, Sendable {
    let activations: Int
    let days: Int
    var qualifies: Bool { activations >= 10 && days >= 5 }
}
