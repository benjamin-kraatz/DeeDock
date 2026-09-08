import Foundation

/// Shared presentation policy keeps engine comparison subject to identical feedback and
/// exclusions. Scores are rankings, not calibrated probabilities.
nonisolated enum LauncherSuggestionRanking {
    static func adjust(_ raw: [String: Double], context: LauncherSuggestionContext,
                       feedback: [LauncherSuggestionFeedback], excluded: Set<String>, now: Date,
                       includeNonPositive: Bool = false) -> [String: Double] {
        let cutoff = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        var scores = raw.filter { $0.value.isFinite && $0.value > 0 && !excluded.contains($0.key) && $0.key != context.foregroundID }
        let maximum = scores.values.max() ?? 1
        scores = scores.mapValues { $0 / max(maximum, 0.001) }
        for (id, score) in scores {
            let recency = context.secondsSinceUse[id].map { 0.1 * exp(-max(0, $0) / 3600) } ?? 0
            let running = context.runningIDs.contains(id) ? 0.025 : 0
            scores[id] = score + recency + running
        }
        // Negative feedback matches the captured context; it never becomes a global ban.
        for item in feedback where item.date > cutoff && item.date <= now && item.context.date > cutoff && item.context.date <= now {
            guard !excluded.contains(item.appID), item.appID != context.foregroundID,
                  item.context.foregroundID == context.foregroundID, item.context.modeID == context.modeID,
                  item.context.weekday == context.weekday, item.context.hour / 3 == context.hour / 3 else { continue }
            let decay = exp(-now.timeIntervalSince(item.date) / (21 * 86400))
            scores[item.appID, default: 0] += (item.kind == .useful ? 0.35 : -1.5) * decay
        }
        return scores.filter { $0.value.isFinite && (includeNonPositive || $0.value > 0) }
    }

    static func sortedIDs(_ scores: [String: Double]) -> [String] {
        scores.keys.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0]! > scores[$1]! }
    }

    /// Core ML kNN has no per-example age weights. Apply an explicit mean age factor for each
    /// label before the shared normalization. This favors labels with recent evidence but is
    /// not equivalent to weighting individual neighbors, which remains a comparison limitation.
    @concurrent static func coreML(context: LauncherSuggestionContext, document: LauncherSuggestionDocument,
                                  excluded: Set<String>, now: Date, engine: LauncherSuggestionCoreML) async throws -> [String] {
        try Task.checkCancellation()
        let cutoff = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        let examples = Array(document.examples.filter {
            $0.date > cutoff && $0.date <= now && $0.context.date > cutoff && $0.context.date <= now
                && !excluded.contains($0.targetID)
        }.suffix(10_000))
        let raw = try await engine.scores(context: context, examples: examples, now: now)
        try Task.checkCancellation()
        var age: [String: (sum: Double, count: Int)] = [:]
        for example in examples {
            let previous = age[example.targetID] ?? (0, 0)
            age[example.targetID] = (previous.sum + exp(-now.timeIntervalSince(example.date) / (21 * 86400)), previous.count + 1)
        }
        let decayed = raw.reduce(into: [String: Double]()) { result, item in
                guard item.key != "__no_suggestion__" else { return }
                guard let factor = age[item.key], factor.count > 0 else { return }
                result[item.key] = item.value * factor.sum / Double(factor.count)
            }
        return sortedIDs(adjust(decayed, context: context, feedback: document.feedback, excluded: excluded, now: now))
    }
}
