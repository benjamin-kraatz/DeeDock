import CoreML
import Foundation
import Darwin
import Synchronization

/// Per-request measurements from the actual Core ML execution, never a shared last trace.
nonisolated struct LauncherSuggestionCoreMLResult: Sendable {
    let scores: [String: Double]
    /// Includes input preparation, cache lookup, and any wait for a model rebuild.
    let preparationMilliseconds: Double
    let inferenceMilliseconds: Double
    /// True only when a completed model was already cached for this exact training input.
    let cacheReused: Bool
    /// Read from the loaded model. Nil when empty history required no model execution.
    let effectiveNeighbors: Int?
}

/// On-device nearest-neighbor alternative. Personalized models live only in this actor;
/// every changed training snapshot rebuilds from the empty bundled seed to forget removals.
actor LauncherSuggestionCoreML {
    nonisolated static let version = "coreml-knn-v1"

    nonisolated enum Failure: Error {
        case missingSeed
        case updateTimedOut
        case missingProbabilities
        case missingNeighborParameter
        case superseded
    }

    private struct TrainingSnapshot: Encodable {
        let examples: [LauncherSuggestionExample]
        let numberOfNeighbors: Int
    }

    private let seedURL: URL?
    private var model: MLModel?
    private var trainingSnapshot: Data?
    private var generation = UUID()
    private var training: (snapshot: Data, generation: UUID, task: Task<Void, Error>)?

    /// Removes crash leftovers without touching another live process's training directory.
    /// Call during store startup/reset; each rebuild also runs this before creating files.
    @concurrent static func removeAbandonedTrainingFiles(in root: URL = FileManager.default.temporaryDirectory) async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("DDock-Suggestions-") {
            let suffix = String(file.lastPathComponent.dropFirst("DDock-Suggestions-".count))
            if UUID(uuidString: suffix) != nil {
                try? FileManager.default.removeItem(at: file)
            } else if let separator = suffix.firstIndex(of: "-"),
                      let process = Int32(suffix[..<separator]), process > 0,
                      UUID(uuidString: String(suffix[suffix.index(after: separator)...])) != nil,
                      kill(process, 0) == -1 && errno == ESRCH {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// A compiled model URL can be injected by focused tests. Production uses the bundled seed.
    init(seedURL: URL? = nil) { self.seedURL = seedURL }

    /// Cancels owned learning and waits for its temporary files to be removed.
    func reset() async {
        let pending = training?.task
        generation = UUID()
        training?.task.cancel()
        training = nil
        trainingSnapshot = nil
        model = nil
        _ = await pending?.result
    }

    /// Returns genuine Core ML class votes, before common feedback and recency policy.
    /// The actor keeps feature construction, updating, disk access, and prediction off MainActor.
    /// Neighbor count is clamped to 1...100 and is part of the model cache identity.
    func scores(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample], now: Date, numberOfNeighbors: Int = 15) async throws -> [String: Double] {
        try await prediction(context: context, examples: examples, now: now, numberOfNeighbors: numberOfNeighbors).scores
    }

    /// Scores and measures this request. Preparation includes shared rebuild waits; inference
    /// measures only the actual Core ML prediction call, excluding the common ranking policy.
    func prediction(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample], now: Date,
                    numberOfNeighbors: Int = 15) async throws -> LauncherSuggestionCoreMLResult {
        let preparationStart = ContinuousClock.now
        try Task.checkCancellation()
        let cutoff = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        let retained = Array(examples.filter {
            $0.date > cutoff && $0.date <= now && $0.context.date > cutoff && $0.context.date <= now
        }.suffix(10_000))
        guard !retained.isEmpty else {
            await reset()
            return .init(scores: [:], preparationMilliseconds: Self.milliseconds(since: preparationStart),
                         inferenceMilliseconds: 0, cacheReused: false, effectiveNeighbors: nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let neighbors = min(100, max(1, numberOfNeighbors))
        let snapshot = try encoder.encode(TrainingSnapshot(examples: retained, numberOfNeighbors: neighbors))
        let cacheReused = trainingSnapshot == snapshot && model != nil
        if !cacheReused {
            if training?.snapshot != snapshot {
                training?.task.cancel()
                let request = UUID()
                generation = request
                // One owned update serves simultaneous presentations on different displays.
                // Reset cancels it; cancellation of one waiter must not cancel other waiters.
                let task = Task {
                    let rebuilt = try await self.rebuild(retained, numberOfNeighbors: neighbors)
                    try Task.checkCancellation()
                    guard self.generation == request else { throw Failure.superseded }
                    self.model = rebuilt
                    self.trainingSnapshot = snapshot
                }
                training = (snapshot, request, task)
            }
            guard let active = training else { throw Failure.superseded }
            do {
                try await active.task.value
                try Task.checkCancellation()
                guard generation == active.generation else { throw Failure.superseded }
                training = nil
            } catch {
                if training?.generation == active.generation { training = nil }
                throw error
            }
        }
        try Task.checkCancellation()
        guard let model else { throw Failure.superseded }
        let predictionGeneration = generation
        guard let effectiveNeighbors = try model.parameterValue(for: .numberOfNeighbors) as? NSNumber,
              effectiveNeighbors.intValue > 0 else { throw Failure.missingNeighborParameter }
        let input = try Self.features(context)
        let preparationMilliseconds = Self.milliseconds(since: preparationStart)
        let inferenceStart = ContinuousClock.now
        let prediction = try await model.prediction(from: input)
        let inferenceMilliseconds = Self.milliseconds(since: inferenceStart)
        try Task.checkCancellation()
        guard generation == predictionGeneration else { throw Failure.superseded }
        guard let probabilities = prediction.featureValue(for: "appIdentityProbs"), probabilities.type == .dictionary else {
            throw Failure.missingProbabilities
        }
        let scores = probabilities.dictionaryValue.reduce(into: [String: Double]()) { result, entry in
            guard let label = entry.key as? String, label != "__no_suggestion__",
                  entry.value.doubleValue.isFinite, entry.value.doubleValue > 0 else { return }
            result[label] = entry.value.doubleValue
        }
        return .init(scores: scores, preparationMilliseconds: preparationMilliseconds,
                     inferenceMilliseconds: inferenceMilliseconds, cacheReused: cacheReused,
                     effectiveNeighbors: effectiveNeighbors.intValue)
    }

    nonisolated private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private func rebuild(_ examples: [LauncherSuggestionExample], numberOfNeighbors: Int) async throws -> MLModel {
        if seedURL == nil { await Self.removeAbandonedTrainingFiles() }
        try Task.checkCancellation()
        guard let seed = seedURL ?? Bundle.main.url(forResource: "LauncherSuggestions", withExtension: "mlmodelc") else {
            throw Failure.missingSeed
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DDock-Suggestions-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // The callback gate prevents any write after cancellation returns, so removal cannot
        // race a late Core ML callback that would recreate learned files after privacy reset.
        defer { try? FileManager.default.removeItem(at: directory) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var current = seed
        for start in stride(from: 0, to: examples.count, by: 256) {
            try Task.checkCancellation()
            let end = min(start + 256, examples.count)
            let records = try examples[start..<end].map { try Self.features($0.context, label: $0.targetID) }
            let destination = directory.appendingPathComponent("batch-\(start).mlmodelc")
            let update = LauncherSuggestionModelUpdate()
            guard ContinuousClock.now < deadline else { throw Failure.updateTimedOut }
            try await update.run(source: current, records: records, destination: destination, deadline: deadline, numberOfNeighbors: numberOfNeighbors)
            try Task.checkCancellation()
            if current != seed { try FileManager.default.removeItem(at: current) }
            current = destination
        }
        return try MLModel(contentsOf: current, configuration: Self.configuration(numberOfNeighbors: numberOfNeighbors))
    }

    nonisolated private static func configuration(numberOfNeighbors: Int) -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        configuration.parameters = [.numberOfNeighbors: NSNumber(value: numberOfNeighbors)]
        return configuration
    }

    nonisolated private static func features(_ context: LauncherSuggestionContext, label: String? = nil) throws -> MLDictionaryFeatureProvider {
        let array = try MLMultiArray(shape: [256], dataType: .float32)
        for (index, value) in context.featureVector.enumerated() { array[index] = NSNumber(value: value) }
        var dictionary: [String: Any] = ["context": array]
        if let label { dictionary["appIdentity"] = label }
        return try MLDictionaryFeatureProvider(dictionary: dictionary)
    }
}

/// Bridges Core ML's callback API without waiting for its cancellation callback (which may
/// never arrive). The mutex owns every task, continuation, and write; no model crosses it.
nonisolated private final class LauncherSuggestionModelUpdate: Sendable {
    private struct State {
        var finished = false
        var task: MLUpdateTask?
        var continuation: CheckedContinuation<Void, Error>?
    }
    private let state = Mutex(State())

    func run(source: URL, records: [MLFeatureProvider], destination: URL, deadline: ContinuousClock.Instant, numberOfNeighbors: Int) async throws {
        let timeout = Task { @concurrent [self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            finish(error: LauncherSuggestionCoreML.Failure.updateTimedOut)
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.withLock { state in
                    guard !state.finished else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    state.continuation = continuation
                    do {
                        let configuration = MLModelConfiguration()
                        configuration.computeUnits = .cpuOnly
                        configuration.parameters = [.numberOfNeighbors: NSNumber(value: numberOfNeighbors)]
                        let task = try MLUpdateTask(forModelAt: source,
                                                    trainingData: MLArrayBatchProvider(array: records),
                                                    configuration: configuration) { [self] context in
                            // Scheduling separates a possibly inline completion from resume's
                            // gate. The mutex transfers callback ownership without unsafe Sendable.
                            let result = Mutex<MLUpdateContext?>(context)
                            DispatchQueue.global(qos: .utility).async { [self] in
                                result.withLock { result in
                                    if let context = result { complete(context, destination: destination) }
                                    result = nil
                                }
                            }
                        }
                        state.task = task
                        task.resume()
                    } catch {
                        state.finished = true
                        state.continuation = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            // Cancellation can originate on MainActor. Keep its caller out of the write gate;
            // reset still awaits this operation and its cleanup before completing.
            DispatchQueue.global(qos: .utility).async {
                self.finish(error: CancellationError())
            }
        }
    }

    private func complete(_ context: MLUpdateContext, destination: URL) {
        state.withLock { state in
            guard !state.finished else { return }
            state.finished = true
            let continuation = state.continuation
            state.continuation = nil
            state.task = nil
            do {
                if let error = context.task.error { throw error }
                try context.model.write(to: destination)
                continuation?.resume()
            } catch {
                continuation?.resume(throwing: error)
            }
        }
    }

    private func finish(error: Error) {
        // Cancel outside the gate: Core ML is allowed to invoke completion synchronously.
        let task: MLUpdateTask? = state.withLock { state in
            guard !state.finished else { return nil }
            state.finished = true
            let task = state.task
            state.task = nil
            state.continuation?.resume(throwing: error)
            state.continuation = nil
            return task
        }
        task?.cancel()
    }
}
