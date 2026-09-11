import Foundation
import Testing
import Darwin
@testable import DeeDock

struct LauncherSuggestionCoreMLTests {
    @Test("Simultaneous displays share a completed Core ML update")
    func concurrentPresentations() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let context = context(now)
        let records = examples(context: context, labels: ["app.first", "app.second", "app.third"])
        async let first = engine.scores(context: context, examples: records, now: now)
        async let second = engine.scores(context: context, examples: records, now: now)
        let (firstScores, secondScores) = try await (first, second)
        #expect(Set(firstScores.keys) == ["app.first", "app.second", "app.third"])
        #expect(firstScores == secondScores)
        await engine.reset()
    }

    @Test("Orphan cleanup preserves live processes and unrelated files")
    func isolatedOrphanCleanup() async throws {
        let deadPID = Int32.max
        let probe = kill(deadPID, 0)
        let probeError = errno
        try #require(probe == -1 && probeError == ESRCH)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("DDock-Suggestions-\(UUID().uuidString)")
        let abandoned = directory.appendingPathComponent("DDock-Suggestions-\(deadPID)-\(UUID().uuidString)")
        let live = directory.appendingPathComponent("DDock-Suggestions-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        let unrelated = directory.appendingPathComponent("unrelated-\(UUID().uuidString)")
        for folder in [legacy, abandoned, live, unrelated] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("synthetic test data".utf8).write(to: folder.appendingPathComponent("marker"))
        }
        await LauncherSuggestionCoreML.removeAbandonedTrainingFiles(in: directory)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: live.appendingPathComponent("marker").path))
        #expect(FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("marker").path))
    }

    @Test("Core ML learns dynamic identities and reuses its completed model")
    func dynamicLabelsAndReuse() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let context = context(now)
        let records = examples(context: context, labels: ["app.first", "app.second", "app.third"])
        let first = try await engine.scores(context: context, examples: records, now: now)
        #expect(Set(first.keys) == ["app.first", "app.second", "app.third"])
        #expect(first.values.allSatisfy { $0.isFinite && $0 > 0 })
        let reused = try await engine.scores(context: context, examples: records, now: now)
        #expect(first == reused)
        let otherContext = LauncherSuggestionContext(date: now, foregroundID: "another.source", modeID: "other")
        let varied = try await engine.scores(context: otherContext, examples: records, now: now)
        #expect(Set(varied.keys).isSubset(of: Set(first.keys)))
        #expect(!varied.isEmpty)
    }

    @Test("Rebuilding Core ML forgets removed and expired identities")
    func rebuildForgets() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let context = context(now)
        let first = try await engine.scores(context: context,
            examples: examples(context: context, labels: ["removed", "kept"]), now: now)
        #expect(first["removed"] != nil)
        let expiredDate = now.addingTimeInterval(-LauncherSuggestionDocument.retention - 1)
        var replacement = examples(context: context, labels: ["kept", "new"])
        replacement += examples(context: self.context(expiredDate), labels: ["expired"])
        let rebuilt = try await engine.scores(context: context, examples: replacement, now: now)
        #expect(Set(rebuilt.keys) == ["kept", "new"])
        let empty = try await engine.scores(context: context, examples: [], now: now)
        #expect(empty.isEmpty)
        let afterEmpty = try await engine.scores(context: context,
            examples: examples(context: context, labels: ["fresh"]), now: now)
        #expect(Set(afterEmpty.keys) == ["fresh"])
    }

    @Test("Cancellation and reset do not publish a partially trained model")
    func cancellationAndReset() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let context = context(now)
        let records = examples(context: context, labels: Array(repeating: "retired", count: 2_000))
        let canceled = Task { try await engine.scores(context: context, examples: records, now: now) }
        canceled.cancel()
        await #expect(throws: CancellationError.self) { try await canceled.value }
        let pending = Task { try await engine.scores(context: context, examples: records, now: now) }
        await Task.yield()
        pending.cancel()
        await engine.reset()
        // The request may have completed before cancellation; regardless, its model must not
        // contaminate a later completed rebuild after the explicit reset.
        _ = await pending.result
        let fresh = try await engine.scores(context: context,
            examples: examples(context: context, labels: ["fresh"]), now: now)
        #expect(Set(fresh.keys) == ["fresh"])
    }

    @Test("Core ML bounds learning to the newest ten thousand examples")
    func boundedHistory() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let context = context(now)
        let records = examples(context: context, labels: ["outside.cap"] + Array(repeating: "retained", count: 10_000))
        let result = try await engine.scores(context: context, examples: records, now: now)
        #expect(Set(result.keys) == ["retained"])
    }

    @Test("Core ML neighbor count changes votes and invalidates its cached model")
    func configurableNeighborCount() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let query = context(now)
        var closest = query
        closest.hour = 9
        var farther = query
        farther.hour = 8
        let records = examples(context: closest, labels: ["closest"])
            + examples(context: farther, labels: Array(repeating: "farther", count: 4))
        let one = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 1)
        #expect(Set(one.keys) == ["closest"])
        let five = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 5)
        #expect(Set(five.keys) == ["closest", "farther"])
        #expect(try #require(five["closest"]) < #require(one["closest"]))
        // Reusing identical examples with a different k must not reuse the preceding model.
        let backToOne = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 1)
        #expect(backToOne == one)
        let belowRange = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 0)
        #expect(belowRange == one)
        let maximum = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 100)
        let aboveRange = try await engine.scores(context: query, examples: records, now: now, numberOfNeighbors: 1_001)
        #expect(aboveRange == maximum)
    }

    @Test("Core ML diagnostics describe each request and read the effective model parameter")
    func perRequestDiagnostics() async throws {
        let engine = LauncherSuggestionCoreML(seedURL: try LauncherSuggestionTestSeed.url())
        let now = Date()
        let query = context(now)
        let records = examples(context: query, labels: ["next"])
        let cold = try await engine.prediction(context: query, examples: records, now: now, numberOfNeighbors: 7)
        #expect(!cold.cacheReused)
        #expect(cold.effectiveNeighbors == 7)
        let cached = try await engine.prediction(context: query, examples: records, now: now, numberOfNeighbors: 7)
        #expect(cached.cacheReused)
        #expect(cached.effectiveNeighbors == 7)
        #expect(cold.scores == cached.scores)
        let changed = try await engine.prediction(context: query, examples: records, now: now, numberOfNeighbors: 1_001)
        #expect(!changed.cacheReused)
        #expect(changed.effectiveNeighbors == 100)
        let empty = try await engine.prediction(context: query, examples: [], now: now)
        #expect(empty.effectiveNeighbors == nil)
        #expect(!empty.cacheReused)
        #expect(empty.scores.isEmpty)
        #expect(empty.inferenceMilliseconds == 0)
        for result in [cold, cached, changed, empty] {
            #expect(result.preparationMilliseconds.isFinite && result.preparationMilliseconds >= 0)
            #expect(result.inferenceMilliseconds.isFinite && result.inferenceMilliseconds >= 0)
        }
        // Later requests cannot overwrite a result that the inspector has already captured.
        #expect(cold.effectiveNeighbors == 7 && !cold.cacheReused)
    }

    private func context(_ date: Date) -> LauncherSuggestionContext {
        LauncherSuggestionContext(date: date, foregroundID: "source", modeID: "work", hour: 10, weekday: 2)
    }

    private func examples(context: LauncherSuggestionContext, labels: [String]) -> [LauncherSuggestionExample] {
        labels.map { LauncherSuggestionExample(context: context, targetID: $0, date: context.date) }
    }
}

/// The isolated runner supplies its compiled model. Xcode runs the tests hosted in DDock, so the
/// seed comes from the app bundle, the same place the app loads it from.
enum LauncherSuggestionTestSeed {
    static func url() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["DEE26_COREML_SEED_URL"] {
            return URL(fileURLWithPath: path)
        }
        return try #require(Bundle.main.url(forResource: "LauncherSuggestions", withExtension: "mlmodelc"))
    }
}
