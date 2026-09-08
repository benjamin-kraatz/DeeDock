import Foundation

/// Chosen local predictor: decayed frequency, transitions, time, and mode, with explicit
/// context-bound feedback. It rebuilds from retained examples for every prediction, so no
/// expired aggregate or personalized model can outlive its source data.
nonisolated enum LauncherSuggestionBaseline {
    static let version = "baseline-v1"

    static func scores(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample],
                       feedback: [LauncherSuggestionFeedback], excluded: Set<String>, now: Date) -> [String: Double] {
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
        // Normalize before feedback so a rejection remains effective with a long history.
        let maximum = scores.values.max() ?? 1
        scores = scores.mapValues { $0 / max(maximum, 0.001) }
        for (id, score) in scores {
            let recency = context.secondsSinceUse[id].map { 0.1 * exp(-$0 / 3600) } ?? 0
            let running = context.runningIDs.contains(id) ? 0.025 : 0
            scores[id] = score + recency + running
        }
        // A feedback context is intentionally narrow; changing foreground, mode, weekday, or
        // time band stops a negative signal from becoming a global app exclusion.
        for item in feedback where item.date > cutoff && item.date <= now && item.context.date > cutoff && item.context.date <= now {
            guard !excluded.contains(item.appID), item.appID != context.foregroundID,
                  item.context.foregroundID == context.foregroundID, item.context.modeID == context.modeID,
                  item.context.weekday == context.weekday, item.context.hour / 3 == context.hour / 3 else { continue }
            let decay = exp(-now.timeIntervalSince(item.date) / (21 * 86400))
            scores[item.appID, default: 0] += (item.kind == .useful ? 0.35 : -1.5) * decay
        }
        return scores.filter { $0.value > 0 }
    }

    @concurrent static func rank(context: LauncherSuggestionContext, document: LauncherSuggestionDocument,
                                excluded: Set<String>, now: Date) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let values = scores(context: context, examples: document.examples, feedback: document.feedback, excluded: excluded, now: now)
        guard !Task.isCancelled else { return [] }
        return values.keys.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0]! > values[$1]! }
    }
}
