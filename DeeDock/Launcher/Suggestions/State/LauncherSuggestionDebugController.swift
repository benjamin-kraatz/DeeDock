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
    var source: LauncherSuggestionDebugSource = .realHistory
    /// Revealed only after chronological prediction, never given to either engine as input.
    var expectedTargetID: String? = nil
}

/// Owns frozen comparisons and isolated generated history. All operations use a separate
/// Core ML instance and never call the live recorder, repository, feedback, or impression paths.
@MainActor @Observable
final class LauncherSuggestionDebugController {
    private(set) var snapshot: LauncherSuggestionDebugSnapshot?
    private(set) var busy = false
    private(set) var failed = false
    private(set) var source = LauncherSuggestionDebugSource.realHistory
    private(set) var configuration = LauncherSuggestionSyntheticConfiguration()
    private let synthetic = LauncherSuggestionSyntheticSession()
    var playback: LauncherSuggestionSyntheticPlayback? { synthetic.playback }
    @ObservationIgnored private var latest: Input?
    @ObservationIgnored private var frozen: Input?
    @ObservationIgnored private var task: Task<Void, Never>?
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
        var source: LauncherSuggestionDebugSource = .realHistory

        func snapshot(tuning: LauncherSuggestionTuning, baseline: LauncherSuggestionEvaluation?,
                      coreML: LauncherSuggestionEvaluation?, outcome: String? = nil) -> LauncherSuggestionDebugSnapshot {
            let examples = LauncherSuggestionEvidence.retainedExamples(document: document, excluded: excluded, now: date)
            return .init(date: date, context: context, exampleCount: examples.count,
                         firstExampleDate: examples.map(\.date).min(), lastExampleDate: examples.map(\.date).max(),
                         tuning: tuning, baseline: baseline, coreML: coreML, history: examples,
                         source: source, expectedTargetID: outcome)
        }
    }

    func capture(context: LauncherSuggestionContext, document: LauncherSuggestionDocument, excluded: Set<String>,
                 now: Date, seedURL: URL?, tuning: LauncherSuggestionTuning, evaluation: LauncherSuggestionEvaluation?) {
        latest = Input(context: context, document: document, excluded: excluded, date: now,
                       seedURL: seedURL, evaluation: evaluation, tuning: tuning)
        if source == .realHistory && snapshot == nil { freezeLatest() }
    }

    /// Explicitly replaces the frozen real input with the latest actual Launcher request.
    func freezeLatest() {
        guard source == .realHistory else { return }
        cancel(preserveSnapshot: true)
        frozen = latest
        guard let frozen else { snapshot = nil; return }
        snapshot = frozen.snapshot(tuning: frozen.tuning,
                                   baseline: frozen.evaluation?.engine == .baseline ? frozen.evaluation : nil,
                                   coreML: frozen.evaluation?.engine == .coreML ? frozen.evaluation : nil)
    }

    func setSource(_ value: LauncherSuggestionDebugSource, tuning: LauncherSuggestionTuning, seedURL: URL?) {
        guard value != source else { return }
        cancel(preserveSnapshot: true)
        source = value
        snapshot = nil; frozen = nil
        if value == .realHistory { freezeLatest() }
        else { inspectSynthetic(tuning: tuning, seedURL: seedURL) }
    }

    /// Reset aggregate chronology when settings change, preserving the frozen comparison.
    func tuningChanged(_ tuning: LauncherSuggestionTuning) { synthetic.prepare(tuning: tuning) }

    /// Editing generation controls leaves the existing scenario intact until Generate is used.
    func setConfiguration(_ value: LauncherSuggestionSyntheticConfiguration) {
        guard value.clamped != configuration else { return }
        cancel(preserveSnapshot: true)
        configuration = value.clamped
    }

    func generate(tuning: LauncherSuggestionTuning, seedURL: URL?) async {
        guard source == .synthetic else { return }
        cancel(preserveSnapshot: true)
        let epoch = generation, configuration = configuration
        busy = true
        let operation = Task { [weak self] in
            let dataset = await Self.generateDataset(configuration)
            guard let self, !Task.isCancelled, generation == epoch else { return }
            synthetic.load(dataset)
            inspectSynthetic(tuning: tuning, seedURL: seedURL)
        }
        task = operation
        await finish(operation, epoch: epoch)
    }

    @concurrent nonisolated private static func generateDataset(_ configuration: LauncherSuggestionSyntheticConfiguration) async -> LauncherSuggestionSyntheticDataset {
        LauncherSuggestionSyntheticGenerator.generate(configuration)
    }

    func advance(days: Int, tuning: LauncherSuggestionTuning, seedURL: URL?) {
        guard source == .synthetic else { return }
        cancel(preserveSnapshot: true)
        synthetic.advance(days: days)
        inspectSynthetic(tuning: tuning, seedURL: seedURL)
    }

    func restart(tuning: LauncherSuggestionTuning, seedURL: URL?) {
        guard source == .synthetic else { return }
        cancel(preserveSnapshot: true)
        synthetic.restart()
        inspectSynthetic(tuning: tuning, seedURL: seedURL)
    }

    private func inspectSynthetic(tuning: LauncherSuggestionTuning, seedURL: URL?) {
        guard let context = synthetic.inspectionContext else { return }
        let input = syntheticInput(context: context, tuning: tuning, seedURL: seedURL)
        frozen = input
        snapshot = input.snapshot(tuning: tuning, baseline: nil, coreML: nil)
    }

    private func syntheticInput(context: LauncherSuggestionContext, tuning: LauncherSuggestionTuning, seedURL: URL?) -> Input {
        Input(context: context, document: synthetic.document, excluded: [], date: context.date,
              seedURL: seedURL, evaluation: nil, tuning: tuning, source: .synthetic)
    }

    func replay(tuning: LauncherSuggestionTuning) async {
        guard let input = frozen else { return }
        // Simulated time is independent of wall time. Real snapshots retain the privacy expiry.
        guard input.source == .synthetic || input.date > Date().addingTimeInterval(-LauncherSuggestionDocument.retention) else {
            cancel(preserveSnapshot: false)
            return
        }
        cancel(preserveSnapshot: true)
        let epoch = generation
        let model = LauncherSuggestionCoreML(seedURL: input.seedURL)
        self.model = model
        busy = true
        let outcome = snapshot?.expectedTargetID
        let operation = Task { [weak self] in
            let result = await Self.evaluate(input, tuning: tuning, model: model, outcome: outcome)
            await model.reset()
            guard let self, !Task.isCancelled, generation == epoch else { return }
            snapshot = result
            failed = result.baseline == nil || result.coreML == nil
        }
        task = operation
        await finish(operation, epoch: epoch)
    }

    /// Predict each generated outcome before learning it. Tuning changes restart chronology
    /// so one metric never mixes results from different threshold or neighbor settings.
    func play(all: Bool, tuning: LauncherSuggestionTuning, seedURL: URL?) async {
        guard source == .synthetic, synthetic.dataset != nil else { return }
        cancel(preserveSnapshot: true)
        synthetic.prepare(tuning: tuning)
        let epoch = generation
        let model = LauncherSuggestionCoreML(seedURL: seedURL)
        self.model = model
        busy = true
        let operation = Task { [weak self] in
            guard let self else { return }
            repeat {
                guard !Task.isCancelled, generation == epoch, let outcome = synthetic.next else { break }
                // The future label is held outside this input and outside the engine calls.
                let input = syntheticInput(context: outcome.context, tuning: tuning, seedURL: seedURL)
                let result = await Self.evaluate(input, tuning: tuning, model: model, outcome: outcome.targetID)
                guard !Task.isCancelled, generation == epoch else { break }
                synthetic.reveal(outcome, baseline: result.baseline, coreML: result.coreML)
                frozen = input
                snapshot = result
                failed = result.baseline == nil || result.coreML == nil
                if !all { break }
                await Task.yield()
            } while true
            await model.reset()
        }
        task = operation
        await finish(operation, epoch: epoch)
    }

    @concurrent nonisolated private static func evaluate(_ input: Input, tuning: LauncherSuggestionTuning,
                                                         model: LauncherSuggestionCoreML, outcome: String?) async -> LauncherSuggestionDebugSnapshot {
        let baseline = try? await LauncherSuggestionEvidence.prediction(engine: .baseline, context: input.context,
            document: input.document, excluded: input.excluded, now: input.date, tuning: tuning, coreML: model)
        let coreML = try? await LauncherSuggestionEvidence.prediction(engine: .coreML, context: input.context,
            document: input.document, excluded: input.excluded, now: input.date, tuning: tuning, coreML: model)
        return input.snapshot(tuning: tuning, baseline: baseline, coreML: coreML, outcome: outcome)
    }

    private func finish(_ operation: Task<Void, Never>, epoch: UUID) async {
        await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        guard generation == epoch else { return }
        task = nil; model = nil; busy = false
    }

    /// Privacy invalidation drops both real snapshots and synthetic state. Tuning/source
    /// changes can cancel work while retaining inputs for an explicit replay or regeneration.
    func cancel(preserveSnapshot: Bool = false) {
        generation = UUID()
        task?.cancel(); task = nil
        if let model { Task { await model.reset() } }
        model = nil; busy = false; failed = false
        if !preserveSnapshot { snapshot = nil; latest = nil; frozen = nil; synthetic.clear() }
    }
}
#endif
