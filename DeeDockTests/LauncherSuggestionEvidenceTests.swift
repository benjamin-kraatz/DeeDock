import Foundation
import Testing

struct LauncherSuggestionEvidenceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

#if DEBUG
    @MainActor @Test("Debug tuning clamps, persists through learning reset, and restores owning defaults")
    func tuningPersistence() async throws {
        let suite = "DEE26.tuning.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(store.tuning == LauncherSuggestionTuning())
        #expect(store.engine == .baseline)
        let originalPreferences = defaults.data(forKey: "launcher.suggestions.preferences.v1")
        let outOfRange = LauncherSuggestionTuning(minHistory: -5, minSupport: 500, minDays: -2,
            minAgreement: 4, maxDistance: -1, neighbors: 0)
        store.setTuning(outOfRange)
        #expect(store.tuning == outOfRange.clamped)
        #expect(store.tuning.minHistory >= 0)
        #expect((0...1).contains(store.tuning.minAgreement))
        #expect(store.tuning.maxDistance >= 0)
        #expect(store.tuning.neighbors >= 1)
        // Tuning is separate from the existing consent and engine preference document.
        #expect(defaults.data(forKey: "launcher.suggestions.preferences.v1") == originalPreferences)
        let reloaded = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(reloaded.tuning == store.tuning)
        #expect(reloaded.engine == .baseline)
        #expect(!reloaded.enabled)
        reloaded.reset()
        await reloaded.flush()
        let afterReset = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(afterReset.tuning == outOfRange.clamped)
        afterReset.resetTuning()
        #expect(afterReset.tuning == LauncherSuggestionTuning())
        let restored = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(restored.tuning == LauncherSuggestionTuning())
        #expect(restored.engine == .baseline)
        #expect(!restored.enabled)
    }

    @MainActor @Test("Debug replay freezes inputs and cannot write learning or survive reset")
    func frozenDebugReplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        let date = Date()
        let firstContext = context(date: date)
        var history = LauncherSuggestionDocument()
        history.examples = (0..<8).map { _ in .init(context: firstContext, targetID: "target", date: date) }
        try await repository.save(history, sequence: 1)
        let store = LauncherSuggestionsStore(directory: directory, defaults: nil,
                                              coreMLSeedURL: try LauncherSuggestionTestSeed.url())
        await store.prepare()
        store.setEnabled(true)
        _ = await store.predict(context: firstContext)
        let frozen = try #require(store.debugSnapshot)
        #expect(frozen.exampleCount == 8)
        store.setTuning(permissive)
        #expect(store.debugSnapshot?.history.map(\.id) == frozen.history.map(\.id))
        let secondContext = LauncherSuggestionContext(date: Date(), foregroundID: "other", modeID: "work")
        _ = await store.predict(context: secondContext)
        #expect(store.debugSnapshot?.context == firstContext)
        await store.flush()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(await repository.load())
        await store.replayDebug()
        let replayed = try #require(store.debugSnapshot)
        #expect(replayed.context == firstContext)
        #expect(replayed.history.map(\.id) == frozen.history.map(\.id))
        #expect(replayed.baseline != nil && replayed.coreML != nil)
        store.captureLatestDebugSnapshot()
        #expect(store.debugSnapshot?.context == secondContext)
        await store.flush()
        #expect(try encoder.encode(await repository.load()) == before)
        let replay = Task { await store.replayDebug() }
        await Task.yield()
        store.reset()
        await replay.value
        #expect(store.debugSnapshot == nil)
        #expect(!store.debugBusy)
        await store.flush()
    }
#endif

    @Test("A normalized winning score cannot bypass thin history", arguments: [LauncherSuggestionEngine.baseline, .coreML])
    func thinHistory(_ engine: LauncherSuggestionEngine) throws {
        let result = evaluate(engine, labels: ["target"], raw: ["target": 1])
        #expect(result.rankedIDs.isEmpty)
        let candidate = try #require(result.candidates.first { $0.id == "target" })
        #expect(candidate.reasons.contains(.history))
        #expect(!candidate.eligible)
    }

    @Test("A same-day activation burst does not establish a repeated habit")
    func singleDayBurst() throws {
        let result = evaluate(.coreML, labels: Array(repeating: "target", count: 30), raw: ["target": 1])
        let candidate = try #require(result.candidates.first { $0.id == "target" })
        #expect(candidate.reasons.contains(.days))
        #expect(candidate.distinctDays == 1)
        #expect(result.rankedIDs.isEmpty)
    }

    @Test("Matching support across distinct days passes the configured boundaries")
    func repeatedHabit() throws {
        var document = document(Array(repeating: "target", count: 3))
        let previousDay = now.addingTimeInterval(-86400)
        document.examples += (0..<3).map { _ in
            .init(context: context(date: previousDay), targetID: "target", date: previousDay)
        }
        let tuning = LauncherSuggestionTuning(minHistory: 6, minSupport: 6, minDays: 2,
            minAgreement: 1, maxDistance: 0, neighbors: 15)
        let result = LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: ["target": 1],
            context: context(), document: document, excluded: [], now: now, tuning: tuning)
        #expect(result.rankedIDs == ["target"])
        let candidate = try #require(result.candidates.first)
        #expect(candidate.support == 6)
        #expect(candidate.distinctDays == 2)
        #expect(candidate.reasons.isEmpty)
    }

    @Test("Unanimous neighbors with distant contexts do not justify a suggestion")
    func distantUnanimous() throws {
        var document = document(Array(repeating: "target", count: 30))
        document.examples = document.examples.map {
            var remote = $0.context
            remote.hour = 22
            return LauncherSuggestionExample(context: remote, targetID: $0.targetID, date: $0.date)
        }
        let result = LauncherSuggestionEvidence.evaluate(engine: .coreML, raw: ["target": 1],
            context: context(), document: document, excluded: [], now: now, tuning: .init())
        let candidate = try #require(result.candidates.first { $0.id == "target" })
        #expect(candidate.reasons.contains(.distance))
        #expect(candidate.support == 0)
        #expect(result.rankedIDs.isEmpty)
    }

    @Test("Support is checked for each candidate independently")
    func individualSupport() throws {
        let tuning = LauncherSuggestionTuning(minHistory: 0, minSupport: 3, minDays: 0,
            minAgreement: 0, maxDistance: 2, neighbors: 15)
        let result = evaluate(.baseline, labels: Array(repeating: "supported", count: 10) + ["thin"],
                              raw: ["supported": 1, "thin": 0.9], tuning: tuning)
        #expect(result.rankedIDs == ["supported"])
        let thin = try #require(result.candidates.first { $0.id == "thin" })
        #expect(thin.support == 1)
        #expect(thin.reasons.contains(.support))
    }

    @Test("Local agreement gates each candidate instead of the entire result list")
    func localAgreement() throws {
        let tuning = LauncherSuggestionTuning(minHistory: 0, minSupport: 0, minDays: 0,
            minAgreement: 0.6, maxDistance: 2, neighbors: 15)
        let result = evaluate(.coreML, labels: Array(repeating: "majority", count: 12) + Array(repeating: "minority", count: 3),
                              raw: ["majority": 0.8, "minority": 0.2], tuning: tuning)
        #expect(result.rankedIDs == ["majority"])
        let minority = try #require(result.candidates.first { $0.id == "minority" })
        #expect(minority.reasons.contains(.agreement))
        #expect(abs(minority.agreement - 0.2) < 0.000001)
    }

    @Test("Exclusions and current foreground remain ineligible despite positive scores")
    func exclusions() {
        let result = evaluate(.baseline, labels: ["excluded", "source"], raw: ["excluded": 1, "source": 1],
                              excluded: ["excluded"], tuning: permissive)
        #expect(result.rankedIDs.isEmpty)
        #expect(result.candidates.allSatisfy { !$0.eligible })
    }

    @Test("Positive feedback cannot resurrect a candidate with no raw model evidence")
    func noFeedbackResurrection() {
        var document = document(["target"])
        document.feedback = [.init(date: now, appID: "target", kind: .useful,
            context: context(), modelVersion: "test")]
        for raw in [[String: Double](), ["target": 0.0]] {
            let result = LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: raw,
                context: context(), document: document, excluded: [], now: now, tuning: permissive)
            #expect(result.rankedIDs.isEmpty)
        }
    }

    @Test("Expired observations cannot establish support or recover through feedback")
    func expiredEvidence() {
        let expired = now.addingTimeInterval(-LauncherSuggestionDocument.retention - 1)
        var document = LauncherSuggestionDocument()
        document.examples = [.init(context: context(date: expired), targetID: "expired", date: expired)]
        document.feedback = [.init(date: expired, appID: "expired", kind: .useful,
                                   context: context(date: expired), modelVersion: "test")]
        let tuning = LauncherSuggestionTuning(minHistory: 0, minSupport: 1, minDays: 0,
            minAgreement: 0, maxDistance: 2, neighbors: 15)
        let result = LauncherSuggestionEvidence.evaluate(engine: .coreML, raw: ["expired": 1],
            context: context(), document: document, excluded: [], now: now, tuning: tuning)
        #expect(result.neighbors.isEmpty)
        #expect(result.rankedIDs.isEmpty)
    }

    @Test("Evidence diagnostics and ordering repeat deterministically")
    func deterministicEvidence() {
        let document = document(["a", "b", "a", "b"])
        let first = LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: ["a": 1, "b": 1],
            context: context(), document: document, excluded: [], now: now, tuning: permissive)
        let second = LauncherSuggestionEvidence.evaluate(engine: .baseline, raw: ["b": 1, "a": 1],
            context: context(), document: document, excluded: [], now: now, tuning: permissive)
        #expect(first.rankedIDs == second.rankedIDs)
        #expect(first.neighbors.map(\.id) == second.neighbors.map(\.id))
        #expect(first.candidates.map(\.id) == second.candidates.map(\.id))
        #expect(first.candidates.map(\.finalScore) == second.candidates.map(\.finalScore))
    }

    @Test("Age decay remains visible and negative feedback can remove a supported candidate")
    func decayAndNegativeFeedback() throws {
        let older = now.addingTimeInterval(-42 * 86400)
        var document = LauncherSuggestionDocument()
        document.examples = [.init(context: context(date: older), targetID: "older", date: older),
                             .init(context: context(), targetID: "recent", date: now)]
        document.feedback = [.init(date: now, appID: "recent", kind: .notNow,
                                   context: context(), modelVersion: "test")]
        let result = LauncherSuggestionEvidence.evaluate(engine: .coreML, raw: ["older": 1, "recent": 1],
            context: context(), document: document, excluded: [], now: now, tuning: permissive)
        let oldCandidate = try #require(result.candidates.first { $0.id == "older" })
        let recentCandidate = try #require(result.candidates.first { $0.id == "recent" })
        #expect(oldCandidate.ageFactor < recentCandidate.ageFactor)
        #expect(recentCandidate.feedbackAdjustment == -1.5)
        #expect(!recentCandidate.eligible)
        #expect(result.rankedIDs == ["older"])
    }

    private var permissive: LauncherSuggestionTuning {
        .init(minHistory: 0, minSupport: 0, minDays: 0, minAgreement: 0, maxDistance: 20, neighbors: 15)
    }

    private func context(date: Date? = nil) -> LauncherSuggestionContext {
        LauncherSuggestionContext(date: date ?? now, foregroundID: "source", modeID: "work", hour: 10, weekday: 2)
    }

    private func document(_ labels: [String]) -> LauncherSuggestionDocument {
        var document = LauncherSuggestionDocument()
        document.examples = labels.map { .init(context: context(), targetID: $0, date: now) }
        return document
    }

    private func evaluate(_ engine: LauncherSuggestionEngine, labels: [String], raw: [String: Double],
                          excluded: Set<String> = [], tuning: LauncherSuggestionTuning = .init()) -> LauncherSuggestionEvaluation {
        LauncherSuggestionEvidence.evaluate(engine: engine, raw: raw, context: context(),
            document: document(labels), excluded: excluded, now: now, tuning: tuning)
    }
}
