import Foundation

/// Chosen local predictor: decayed frequency, transitions, time, and mode, with explicit
/// context-bound feedback. It rebuilds from retained examples for every prediction, so no
/// expired aggregate or personalized model can outlive its source data.
nonisolated enum LauncherSuggestionBaseline {
    static let version = "baseline-v1"

    static func scores(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample],
                       feedback: [LauncherSuggestionFeedback], excluded: Set<String>, now: Date) -> [String: Double] {
        LauncherSuggestionRanking.adjust(rawScores(context: context, examples: examples, excluded: excluded, now: now),
                                         context: context, feedback: feedback, excluded: excluded, now: now)
    }

    /// Unnormalized baseline evidence; age decay is already included in these contributions.
    static func rawScores(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample],
                          excluded: Set<String>, now: Date) -> [String: Double] {
        let cutoff = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        var scores: [String: Double] = [:]
        for example in examples {
            guard example.date > cutoff, example.date <= now, example.context.date > cutoff, example.context.date <= now,
                  !excluded.contains(example.targetID), example.targetID != context.foregroundID else { continue }
            let age = now.timeIntervalSince(example.date) / 86400
            let decay = exp(-age / 21)
            let previous = example.context
            let transition = context.foregroundID != nil && previous.foregroundID == context.foregroundID ? 3.0 : 0
            let hourDistance = abs(previous.hour - context.hour)
            let time = min(hourDistance, 24 - hourDistance) <= 2 ? 0.5 : 0
            let weekday = previous.weekday == context.weekday ? 0.25 : 0
            let mode = context.modeID != nil && previous.modeID == context.modeID ? 0.5 : 0
            let recent = Set(previous.recentIDs.prefix(3)).intersection(context.recentIDs.prefix(3)).isEmpty ? 0 : 0.25
            scores[example.targetID, default: 0] += decay * (1 + transition + time + weekday + mode + recent)
        }
        return scores
    }

    @concurrent static func rank(context: LauncherSuggestionContext, document: LauncherSuggestionDocument,
                                excluded: Set<String>, now: Date) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let values = scores(context: context, examples: document.examples, feedback: document.feedback, excluded: excluded, now: now)
        guard !Task.isCancelled else { return [] }
        return LauncherSuggestionRanking.sortedIDs(values)
    }
}
