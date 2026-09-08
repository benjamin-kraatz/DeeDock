#if DEBUG
import Foundation
import Observation

nonisolated enum LauncherSuggestionDebugSource: String, CaseIterable, Sendable {
    case realHistory, synthetic
}

/// Generated-outcome measurements only. Failures are reported separately from abstention.
nonisolated struct LauncherSuggestionSyntheticMetrics: Sendable {
    var predictions = 0
    var offered = 0
    var hits = 0
    var failures = 0
    /// Steps from the generated habit change to the first offered set containing its outcome.
    /// This is a first-hit measurement, not proof of stable adaptation.
    var adaptationSteps: Int?
    var coverage: Double { predictions > failures ? Double(offered) / Double(predictions - failures) : 0 }
    var hitRate: Double? { offered > 0 ? Double(hits) / Double(offered) : nil }

    mutating func record(_ evaluation: LauncherSuggestionEvaluation?, target: String, index: Int, driftIndex: Int?, driftTargetID: String? = nil) {
        predictions += 1
        guard let evaluation else { failures += 1; return }
        let suggestions = Array(evaluation.rankedIDs.prefix(3))
        if !suggestions.isEmpty { offered += 1 }
        if suggestions.contains(target) {
            hits += 1
            if let driftIndex, index >= driftIndex, target == driftTargetID, adaptationSteps == nil {
                adaptationSteps = index - driftIndex + 1
            }
        }
    }
}

nonisolated struct LauncherSuggestionSyntheticPlayback: Sendable {
    var position = 0
    let total: Int
    var baseline = LauncherSuggestionSyntheticMetrics()
    var coreML = LauncherSuggestionSyntheticMetrics()
}

/// In-memory generated history and revealed outcomes. Future outcomes are never included in
/// a prediction document. Advancing the clock ages existing records without regenerating them.
@MainActor @Observable final class LauncherSuggestionSyntheticSession {
    var dataset: LauncherSuggestionSyntheticDataset?
    private(set) var observed: [LauncherSuggestionExample] = []
    private(set) var playback: LauncherSuggestionSyntheticPlayback?
    private(set) var date: Date?
    private var evaluatedTuning: LauncherSuggestionTuning?
    private var futureOffset: TimeInterval = 0

    func load(_ dataset: LauncherSuggestionSyntheticDataset) {
        self.dataset = dataset
        restart()
    }

    func restart() {
        observed = []
        playback = dataset.map { .init(total: $0.future.count) }
        date = dataset?.query.date
        evaluatedTuning = nil
        futureOffset = 0
    }

    func clear() { dataset = nil; restart() }

    func prepare(tuning: LauncherSuggestionTuning) {
        if let evaluatedTuning, evaluatedTuning != tuning { restart() }
        evaluatedTuning = tuning
    }

    func advance(days: Int) {
        guard let date else { return }
        let offset = Double(min(365, max(0, days))) * 86_400
        self.date = date.addingTimeInterval(offset)
        // Shift the remaining schedule too; aging history must not turn four daily
        // outcomes into a burst merely because their original dates are now in the past.
        futureOffset += offset
    }

    var document: LauncherSuggestionDocument {
        var result = LauncherSuggestionDocument()
        result.examples = (dataset?.history ?? []) + observed
        return result
    }

    var inspectionContext: LauncherSuggestionContext? {
        guard let template = dataset?.query, let date else { return nil }
        return Self.context(template, at: date)
    }

    var next: LauncherSuggestionExample? {
        guard let dataset, let playback, playback.position < dataset.future.count else { return nil }
        let template = dataset.future[playback.position]
        let scheduledDate = template.context.date.addingTimeInterval(futureOffset)
        let queryDate = max(date ?? scheduledDate, scheduledDate)
        let context = Self.context(template.context, at: queryDate)
        return .init(id: template.id, context: context, targetID: template.targetID,
                     date: queryDate.addingTimeInterval(3))
    }

    /// Called only after predictions have completed and their generation is still valid.
    func reveal(_ outcome: LauncherSuggestionExample, baseline: LauncherSuggestionEvaluation?, coreML: LauncherSuggestionEvaluation?) {
        guard var playback, let dataset else { return }
        playback.baseline.record(baseline, target: outcome.targetID, index: playback.position, driftIndex: dataset.driftIndex, driftTargetID: dataset.driftTargetID)
        playback.coreML.record(coreML, target: outcome.targetID, index: playback.position, driftIndex: dataset.driftIndex, driftTargetID: dataset.driftTargetID)
        playback.position += 1
        self.playback = playback
        observed.append(outcome)
        date = outcome.date.addingTimeInterval(1)
    }

    private static func context(_ template: LauncherSuggestionContext, at date: Date) -> LauncherSuggestionContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .init(date: date, foregroundID: template.foregroundID, modeID: template.modeID,
                     recentIDs: template.recentIDs, runningIDs: template.runningIDs,
                     hour: calendar.component(.hour, from: date), weekday: calendar.component(.weekday, from: date),
                     foregroundSeconds: template.foregroundSeconds, secondsSinceUse: template.secondsSinceUse,
                     secondsSinceTermination: template.secondsSinceTermination)
    }
}
#endif
