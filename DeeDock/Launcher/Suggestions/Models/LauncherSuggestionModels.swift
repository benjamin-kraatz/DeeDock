import Foundation

/// Metadata captured before an outcome. Identifiers are bundle IDs, never paths or content.
nonisolated struct LauncherSuggestionContext: Codable, Equatable, Sendable {
    let date: Date
    let foregroundID: String?
    let modeID: String?
    var recentIDs: [String] = []
    var runningIDs: [String] = []
    var hour: Int = 0
    var weekday: Int = 1
    var foregroundSeconds: Double? = nil
    var secondsSinceUse: [String: Double] = [:]
    var secondsSinceTermination: [String: Double] = [:]

    /// Fixed signed hashing uses separate, normalized categorical regions. Stable FNV hashing
    /// avoids ordinal identifiers and process-randomized Swift hashes. Collisions remain possible.
    var featureVector: [Float] {
        var values = [Float](repeating: 0, count: 256)
        func put(_ id: String?, offset: Int, count: Int, weight: Float) {
            guard let id else { return }
            let hash = id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            values[offset + Int(hash % UInt64(count))] += hash & (1 << 63) == 0 ? weight : -weight
        }
        let phase = Double(hour) / 24 * .pi * 2
        values[0] = Float(sin(phase)); values[1] = Float(cos(phase))
        values[2 + min(6, max(0, weekday - 1))] = 0.5
        values[9] = Float(min(foregroundSeconds ?? 0, 300) / 300) * 0.25
        put(foregroundID, offset: 16, count: 96, weight: 1)
        for (index, id) in recentIDs.prefix(3).enumerated() {
            put(id, offset: 112, count: 64, weight: 0.5 / Float(index + 1))
        }
        let runningWeight = 0.35 / Float(max(1, runningIDs.count)).squareRoot()
        for id in runningIDs { put(id, offset: 176, count: 48, weight: runningWeight) }
        put(modeID, offset: 224, count: 32, weight: 0.4)
        return values
    }
}

/// A stable foreground activation, paired with the preceding context rather than its own state.
nonisolated struct LauncherSuggestionExample: Codable, Sendable {
    var id = UUID()
    let context: LauncherSuggestionContext
    let targetID: String
    let date: Date
}

nonisolated struct LauncherSuggestionEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case launch, termination, activation, sessionStart, sessionEnd }
    let date: Date
    let kind: Kind
    let appID: String?
    let context: LauncherSuggestionContext
}

nonisolated struct LauncherSuggestionFeedback: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case useful, notNow }
    let date: Date
    let appID: String
    let kind: Kind
    let context: LauncherSuggestionContext
    let modelVersion: String
}

/// Immutable per-presentation ranking and feedback attribution. Generation is the privacy epoch.
nonisolated struct LauncherSuggestionSnapshot: Sendable {
    var id = UUID()
    let context: LauncherSuggestionContext
    let modelVersion: String
    let rankedIDs: [String]
    let createdAt: Date
    let generation: UUID
}

nonisolated struct LauncherSuggestionImpression: Codable, Sendable {
    let id: UUID
    let date: Date
    let appIDs: [String]
    let context: LauncherSuggestionContext
    let modelVersion: String
}

nonisolated struct LauncherSuggestionPromptAnswer: Codable, Sendable {
    let date: Date
    let useful: Bool?
}

/// Behavior only. Deliberate exclusions and consent live separately in preferences.
nonisolated struct LauncherSuggestionDocument: Codable, Sendable {
    var version = 1
    var events: [LauncherSuggestionEvent] = []
    var examples: [LauncherSuggestionExample] = []
    var feedback: [LauncherSuggestionFeedback] = []
    var impressions: [LauncherSuggestionImpression] = []
    var promptAnswers: [LauncherSuggestionPromptAnswer] = []
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    /// Caps are safety limits, not a guarantee of retaining every event for the entire window.
    /// Future-dated records are retired after wall-clock rollback instead of delaying expiry.
    @discardableResult mutating func expire(now: Date) -> Bool {
        let oldCounts = [events.count, examples.count, feedback.count, impressions.count, promptAnswers.count]
        let cutoff = now.addingTimeInterval(-Self.retention)
        func eligible(_ date: Date) -> Bool { date > cutoff && date <= now }
        events = Array(events.filter { eligible($0.date) && eligible($0.context.date) }.suffix(20_000))
        examples = Array(examples.filter { eligible($0.date) && eligible($0.context.date) }.suffix(10_000))
        feedback = Array(feedback.filter { eligible($0.date) && eligible($0.context.date) }.suffix(2_000))
        impressions = Array(impressions.filter { eligible($0.date) && eligible($0.context.date) }.suffix(2_000))
        promptAnswers = Array(promptAnswers.filter { eligible($0.date) }.suffix(100))
        return oldCounts != [events.count, examples.count, feedback.count, impressions.count, promptAnswers.count]
    }
}
