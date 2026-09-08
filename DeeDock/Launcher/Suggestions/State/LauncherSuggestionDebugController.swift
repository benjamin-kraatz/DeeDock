#if DEBUG
import Foundation
import Observation

/// Frozen, local diagnostics. This type and its owner do not exist in Release builds.
nonisolated struct LauncherSuggestionDebugSnapshot: Sendable {
    let date: Date
    let context: LauncherSuggestionContext
    let exampleCount: Int
    let firstExampleDate: Date?
    let lastExampleDate: Date?
    let tuning: LauncherSuggestionTuning
    let baseline: LauncherSuggestionEvaluation?
    let coreML: LauncherSuggestionEvaluation?
    let history: [LauncherSuggestionExample]
}

/// Owns a frozen comparison and an independent Core ML instance. Replaying never records
/// outcomes or impressions and cannot replace the live Launcher's prediction or model cache.
@MainActor @Observable
final class LauncherSuggestionDebugController {
    private(set) var snapshot: LauncherSuggestionDebugSnapshot?
    private(set) var busy = false
    private(set) var failed = false
    @ObservationIgnored private var latest: Input?
    @ObservationIgnored private var frozen: Input?
    @ObservationIgnored private var task: Task<LauncherSuggestionDebugSnapshot, Never>?
    @ObservationIgnored private var model: LauncherSuggestionCoreML?
    @ObservationIgnored private var generation = UUID()

    nonisolated private struct Input: Sendable {
        let context: LauncherSuggestionContext
        let document: LauncherSuggestionDocument
        let excluded: Set<String>
        let date: Date
        let seedURL: URL?
        let evaluation: LauncherSuggestionEvaluation?
        let tuning: LauncherSuggestionTuning

        func snapshot(tuning: LauncherSuggestionTuning, baseline: LauncherSuggestionEvaluation?,
                      coreML: LauncherSuggestionEvaluation?) -> LauncherSuggestionDebugSnapshot {
            let examples = LauncherSuggestionEvidence.retainedExamples(document: document, excluded: excluded, now: date)
            return .init(date: date, context: context, exampleCount: examples.count,
                         firstExampleDate: examples.map(\.date).min(), lastExampleDate: examples.map(\.date).max(),
                         tuning: tuning, baseline: baseline, coreML: coreML, history: examples)
        }
    }

    func capture(context: LauncherSuggestionContext, document: LauncherSuggestionDocument, excluded: Set<String>,
                 now: Date, seedURL: URL?, tuning: LauncherSuggestionTuning, evaluation: LauncherSuggestionEvaluation?) {
        latest = Input(context: context, document: document, excluded: excluded, date: now,
                       seedURL: seedURL, evaluation: evaluation, tuning: tuning)
        if snapshot == nil { freezeLatest() }
    }

    /// Explicitly replaces the frozen input with the latest actual Launcher request.
    func freezeLatest() {
        cancel(preserveSnapshot: true)
        frozen = latest
        guard let frozen else { snapshot = nil; return }
        snapshot = frozen.snapshot(tuning: frozen.tuning,
                                   baseline: frozen.evaluation?.engine == .baseline ? frozen.evaluation : nil,
                                   coreML: frozen.evaluation?.engine == .coreML ? frozen.evaluation : nil)
    }

    func replay(tuning: LauncherSuggestionTuning) async {
        guard let input = frozen, input.date > Date().addingTimeInterval(-LauncherSuggestionDocument.retention) else {
            cancel(preserveSnapshot: false)
            return
        }
        cancel(preserveSnapshot: true)
        let epoch = generation
        let model = LauncherSuggestionCoreML(seedURL: input.seedURL)
        self.model = model
        busy = true
        let task = Task { @concurrent in
            let baseline = try? await LauncherSuggestionEvidence.prediction(engine: .baseline, context: input.context,
                document: input.document, excluded: input.excluded, now: input.date, tuning: tuning, coreML: model)
            let coreML = try? await LauncherSuggestionEvidence.prediction(engine: .coreML, context: input.context,
                document: input.document, excluded: input.excluded, now: input.date, tuning: tuning, coreML: model)
            await model.reset()
            return input.snapshot(tuning: tuning, baseline: baseline, coreML: coreML)
        }
        self.task = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard generation == epoch else { return }
        self.task = nil; self.model = nil; busy = false
        guard !Task.isCancelled, !task.isCancelled else { return }
        snapshot = result
        failed = result.baseline == nil || result.coreML == nil
    }

    /// Privacy invalidation drops both snapshots and cancels all owned diagnostic work.
    /// Tuning and engine changes can cancel work while retaining the frozen comparison input.
    func cancel(preserveSnapshot: Bool = false) {
        generation = UUID()
        task?.cancel(); task = nil
        if let model { Task { await model.reset() } }
        model = nil; busy = false; failed = false
        if !preserveSnapshot { snapshot = nil; latest = nil; frozen = nil }
    }
}
#endif
