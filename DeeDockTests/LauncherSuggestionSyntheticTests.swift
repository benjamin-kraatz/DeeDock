#if DEBUG
import Foundation
import Testing
@testable import DeeDock

struct LauncherSuggestionSyntheticTests {
    @MainActor @Test("Advancing the synthetic clock preserves remaining daily event spacing")
    func advancedScheduleSpacing() throws {
        let dataset = LauncherSuggestionSyntheticGenerator.generate(.init())
        let session = LauncherSuggestionSyntheticSession()
        session.load(dataset)
        session.advance(days: 91)
        var contexts: [Date] = []
        for _ in 0..<5 {
            let next = try #require(session.next)
            contexts.append(next.context.date)
            session.reveal(next, baseline: nil, coreML: nil)
        }
        #expect(contexts[0].timeIntervalSince(dataset.future[0].context.date) == 91 * 86400)
        #expect(contexts[1].timeIntervalSince(contexts[0]) == 300)
        #expect(contexts[2].timeIntervalSince(contexts[1]) == 300)
        #expect(contexts[3].timeIntervalSince(contexts[2]) == 300)
        #expect(contexts[4].timeIntervalSince(contexts[0]) == 86400)
        #expect(session.dataset?.history.map(\.id) == dataset.history.map(\.id))
        #expect(session.dataset?.history.map(\.date) == dataset.history.map(\.date))
    }

    @MainActor @Test("Full synthetic playback predicts all sixty outcomes before learning each one")
    func fullPlayback() async throws {
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil,
                                              coreMLSeedURL: try LauncherSuggestionTestSeed.url())
        store.setDebugSource(.synthetic)
        var config = LauncherSuggestionSyntheticConfiguration()
        config.exampleCount = 0
        store.setSyntheticConfiguration(config)
        await store.generateSyntheticHistory()
        await store.runSyntheticHistory()
        let progress = try #require(store.syntheticPlayback)
        #expect(progress.position == 60 && progress.total == 60)
        #expect(progress.baseline.predictions == 60 && progress.coreML.predictions == 60)
        #expect(progress.baseline.failures == 0 && progress.coreML.failures == 0)
        #expect(store.debugSnapshot?.exampleCount == 59)
        #expect(store.debugSnapshot?.history.count == 59)
        #expect(!store.debugBusy && !store.debugError)
        #expect(!store.enabled)
    }

    @MainActor @Test("Synthetic model playback predicts before adding the first generated outcome")
    func actualChronologicalSteps() async throws {
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil,
                                              coreMLSeedURL: try LauncherSuggestionTestSeed.url())
        store.setDebugSource(.synthetic)
        var config = LauncherSuggestionSyntheticConfiguration()
        config.exampleCount = 0
        store.setSyntheticConfiguration(config)
        await store.generateSyntheticHistory()
        await store.stepSyntheticHistory()
        let first = try #require(store.debugSnapshot)
        #expect(first.history.isEmpty)
        #expect(first.baseline?.rankedIDs.isEmpty == true)
        #expect(first.coreML?.rankedIDs.isEmpty == true)
        #expect(store.syntheticPlayback?.position == 1)
        await store.stepSyntheticHistory()
        let second = try #require(store.debugSnapshot)
        #expect(second.history.count == 1)
        #expect(second.history.first?.targetID == first.expectedTargetID)
        #expect(store.syntheticPlayback?.position == 2)
        let frozenIDs = second.history.map(\.id)
        var tuning = store.tuning
        tuning.minHistory += 1
        store.setTuning(tuning)
        #expect(store.syntheticPlayback?.position == 0)
        #expect(store.debugSnapshot?.history.map(\.id) == frozenIDs)
        #expect(!store.enabled)
    }

    @Test("A noisy old-target hit does not count as adaptation to the new habit")
    func driftAdaptation() {
        var metrics = LauncherSuggestionSyntheticMetrics()
        metrics.record(evaluation("old"), target: "old", index: 0, driftIndex: 0, driftTargetID: "new")
        #expect(metrics.hits == 1)
        #expect(metrics.adaptationSteps == nil)
        metrics.record(evaluation("new"), target: "new", index: 1, driftIndex: 0, driftTargetID: "new")
        #expect(metrics.hits == 2)
        #expect(metrics.adaptationSteps == 2)
    }

    @MainActor @Test("Synthetic comparison runs with consent off and never changes saved user history")
    func consentAndStorageIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        let date = Date()
        var realHistory = LauncherSuggestionDocument()
        realHistory.examples = [.init(context: .init(date: date, foregroundID: "real.source", modeID: nil),
                                      targetID: "real.target", date: date)]
        try await repository.save(realHistory, sequence: 1)
        let store = LauncherSuggestionsStore(directory: directory, defaults: nil,
                                              coreMLSeedURL: try LauncherSuggestionTestSeed.url())
        await store.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(await repository.load())
        store.setDebugSource(.synthetic)
        var config = LauncherSuggestionSyntheticConfiguration()
        config.exampleCount = 8
        store.setSyntheticConfiguration(config)
        await store.generateSyntheticHistory()
        await store.replayDebug()
        #expect(!store.enabled && !store.isActive)
        #expect(store.debugSnapshot?.source == .synthetic)
        #expect(store.debugSnapshot?.baseline != nil && store.debugSnapshot?.coreML != nil)
        #expect(store.debugSnapshot?.history.contains { $0.targetID == "real.target" } == false)
        await store.stepSyntheticHistory()
        #expect(store.syntheticPlayback?.position == 1)
        #expect(!store.enabled && !store.hasSession)
        await store.flush()
        #expect(try encoder.encode(await repository.load()) == before)
        store.setDebugSource(.realHistory)
        #expect(store.debugSnapshot == nil)
    }

    @MainActor @Test("Synthetic playback cannot publish after cancellation, reset, or source change", arguments: ["cancel", "reset", "source"])
    func stalePlayback(_ action: String) async throws {
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil,
                                              coreMLSeedURL: try LauncherSuggestionTestSeed.url())
        store.setDebugSource(.synthetic)
        await store.generateSyntheticHistory()
        let operation = Task { await store.runSyntheticHistory() }
        for _ in 0..<100 {
            if store.debugBusy { break }
            await Task.yield()
        }
        try #require(store.debugBusy)
        switch action {
        case "source": store.setDebugSource(.realHistory)
        case "reset": store.reset()
        default: store.cancelDebugReplay()
        }
        let stoppedPosition = store.syntheticPlayback?.position
        let stoppedIDs = store.debugSnapshot?.history.map(\.id)
        await operation.value
        #expect(!store.debugBusy)
        #expect(store.syntheticPlayback?.position == stoppedPosition)
        #expect(store.debugSnapshot?.history.map(\.id) == stoppedIDs)
        if action != "cancel" { #expect(store.debugSnapshot == nil) }
        #expect(!store.enabled)
        await store.flush()
    }

    @Test("Exact-distance ties cannot manufacture agreement through app-name ordering")
    func targetNeutralNeighbors() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let context = LauncherSuggestionContext(date: date, foregroundID: "source", modeID: "work", hour: 10, weekday: 2)
        var document = LauncherSuggestionDocument()
        document.examples = (0..<45).map { index in
            let preceding = LauncherSuggestionContext(date: date.addingTimeInterval(Double(index - 45)),
                foregroundID: "source", modeID: "work", hour: 10, weekday: 2)
            return .init(context: preceding, targetID: ["a", "b", "c"][index % 3], date: preceding.date)
        }
        let tuning = LauncherSuggestionTuning(minHistory: 0, minSupport: 0, minDays: 0,
            minAgreement: 0.6, maxDistance: 2, neighbors: 15)
        let result = LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: ["a": 1, "b": 1, "c": 1],
            context: context, document: document, excluded: [], now: date, tuning: tuning)
        #expect(result.rankedIDs.isEmpty)
        #expect(result.neighbors.count == 15)
        for candidate in result.candidates {
            #expect(candidate.support == 5)
            #expect(abs(candidate.agreement - 1.0 / 3) < 0.000001)
            #expect(candidate.reasons.contains(.agreement))
        }
    }

    @Test("Synthetic histories and identities reproduce exactly from their seed", arguments: LauncherSuggestionSyntheticScenario.allCases)
    func deterministicGeneration(_ scenario: LauncherSuggestionSyntheticScenario) throws {
        var config = LauncherSuggestionSyntheticConfiguration()
        config.scenario = scenario
        let first = LauncherSuggestionSyntheticGenerator.generate(config)
        let second = LauncherSuggestionSyntheticGenerator.generate(config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(first.history) == encoder.encode(second.history))
        #expect(try encoder.encode(first.future) == encoder.encode(second.future))
        #expect(first.query == second.query)
        #expect(first.expectedTargetID == second.expectedTargetID)
        let identities = (first.history + first.future).map(\.id)
        #expect(Set(identities).count == identities.count)
    }

    @Test("Generated history is bounded and strictly precedes unseen outcomes")
    func boundsAndChronology() {
        var config = LauncherSuggestionSyntheticConfiguration()
        config.exampleCount = 100_000
        config.days = 1_000
        let dataset = LauncherSuggestionSyntheticGenerator.generate(config)
        #expect(dataset.history.count == 1_000)
        #expect(dataset.configuration.days == 90)
        #expect(dataset.history.allSatisfy { $0.date < config.referenceDate && $0.context.date < $0.date })
        #expect(dataset.future.allSatisfy { $0.date >= config.referenceDate && $0.context.date < $0.date })
        #expect(zip(dataset.history, dataset.history.dropFirst()).allSatisfy { $0.0.date < $0.1.date })
        #expect(zip(dataset.future, dataset.future.dropFirst()).allSatisfy { $0.0.date < $0.1.date })
        config.exampleCount = -1
        #expect(LauncherSuggestionSyntheticGenerator.generate(config).history.isEmpty)
    }

    @Test("Burst history stays within one UTC calendar day")
    func burstDay() {
        var config = LauncherSuggestionSyntheticConfiguration()
        config.scenario = .burst
        config.exampleCount = 1_000
        config.days = 90
        let dataset = LauncherSuggestionSyntheticGenerator.generate(config)
        let days = Set(dataset.history.map { Int(floor($0.date.timeIntervalSince1970 / 86400)) })
        #expect(days.count == 1)
    }

    @Test("Outcome strength cannot leak the generated target into its input context")
    func independentInputs() {
        var weak = LauncherSuggestionSyntheticConfiguration()
        weak.patternStrength = 0
        var strong = weak
        strong.patternStrength = 1
        let weakData = LauncherSuggestionSyntheticGenerator.generate(weak)
        let strongData = LauncherSuggestionSyntheticGenerator.generate(strong)
        #expect(weakData.history.map(\.context) == strongData.history.map(\.context))
        #expect(weakData.future.map(\.context) == strongData.future.map(\.context))
        #expect(weakData.history.map(\.targetID) != strongData.history.map(\.targetID))
    }

    @MainActor @Test("Chronological playback reveals each target only after prediction")
    func noFutureTraining() throws {
        var config = LauncherSuggestionSyntheticConfiguration()
        config.exampleCount = 0
        let session = LauncherSuggestionSyntheticSession()
        session.load(LauncherSuggestionSyntheticGenerator.generate(config))
        #expect(session.document.examples.isEmpty)
        let first = try #require(session.next)
        #expect(session.document.examples.isEmpty)
        session.reveal(first, baseline: nil, coreML: nil)
        #expect(session.document.examples.map(\.id) == [first.id])
        #expect(session.playback?.position == 1)
        let second = try #require(session.next)
        #expect(second.id != first.id)
        #expect(second.context.date > first.date)
        #expect(!session.document.examples.contains { $0.id == second.id })
    }

    @MainActor @Test("Advancing synthetic time expires evidence without regenerating its history")
    func simulatedExpiry() throws {
        let session = LauncherSuggestionSyntheticSession()
        session.load(LauncherSuggestionSyntheticGenerator.generate(.init()))
        let ids = session.document.examples.map(\.id)
        let dates = session.document.examples.map(\.date)
        session.advance(days: 91)
        let context = try #require(session.inspectionContext)
        #expect(session.document.examples.map(\.id) == ids)
        #expect(session.document.examples.map(\.date) == dates)
        let retained = LauncherSuggestionEvidence.retainedExamples(document: session.document, excluded: [], now: context.date)
        #expect(retained.isEmpty)
        #expect(session.playback?.position == 0)
    }

    @Test("Playback metrics distinguish model failure, abstention, and offered hits")
    func metrics() {
        var metrics = LauncherSuggestionSyntheticMetrics()
        metrics.record(nil, target: "target", index: 0, driftIndex: 0, driftTargetID: "target")
        #expect(metrics.predictions == 1 && metrics.failures == 1)
        #expect(metrics.coverage == 0 && metrics.hitRate == nil)
        let empty = LauncherSuggestionEvaluation(engine: .baseline, candidates: [], neighbors: [], elapsedMilliseconds: 0)
        metrics.record(empty, target: "target", index: 1, driftIndex: 0, driftTargetID: "target")
        metrics.record(evaluation("target"), target: "target", index: 2, driftIndex: 0, driftTargetID: "target")
        #expect(metrics.offered == 1 && metrics.hits == 1)
        #expect(metrics.coverage == 0.5 && metrics.hitRate == 1)
        #expect(metrics.adaptationSteps == 3)
        metrics.record(evaluation("other"), target: "target", index: 3, driftIndex: 0, driftTargetID: "target")
        #expect(metrics.predictions == 4 && metrics.failures == 1)
        #expect(metrics.offered == 2 && metrics.hits == 1)
        #expect(abs(metrics.coverage - 2.0 / 3) < 0.000001)
        #expect(metrics.hitRate == 0.5 && metrics.adaptationSteps == 3)
    }

    private func evaluation(_ target: String) -> LauncherSuggestionEvaluation {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let context = LauncherSuggestionContext(date: date, foregroundID: "source", modeID: nil)
        var document = LauncherSuggestionDocument()
        document.examples = [.init(context: context, targetID: target, date: date)]
        return LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: [target: 1], context: context,
            document: document, excluded: [], now: date,
            tuning: .init(minHistory: 0, minSupport: 0, minDays: 0, minAgreement: 0, maxDistance: 20, neighbors: 15))
    }
}
#endif
