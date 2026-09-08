import Foundation
import Testing

@MainActor
struct LauncherSuggestionEngineTests {
    @Test("Shared ranking preserves baseline transition, recency, and feedback scores")
    func baselinePolicyRegression() {
        let now = Date()
        let context = LauncherSuggestionContext(date: now, foregroundID: "source", modeID: "work",
            recentIDs: ["prior"], runningIDs: ["preferred"], hour: 10, weekday: 2,
            secondsSinceUse: ["preferred": 0])
        let unrelated = LauncherSuggestionContext(date: now, foregroundID: "other", modeID: "other", hour: 20, weekday: 3)
        let examples = [LauncherSuggestionExample(context: context, targetID: "preferred", date: now),
                        LauncherSuggestionExample(context: unrelated, targetID: "alternative", date: now),
                        LauncherSuggestionExample(context: context, targetID: "excluded", date: now)]
        let feedback = LauncherSuggestionFeedback(date: now, appID: "preferred", kind: .useful,
                                                  context: context, modelVersion: LauncherSuggestionBaseline.version)
        let scores = LauncherSuggestionBaseline.scores(context: context, examples: examples,
            feedback: [feedback], excluded: ["excluded"], now: now)
        #expect(abs((scores["preferred"] ?? 0) - 1.475) < 0.000001)
        #expect(abs((scores["alternative"] ?? 0) - 1 / 5.5) < 0.000001)
        #expect(scores["excluded"] == nil)
    }

    @Test("Existing consent preferences migrate to the baseline engine")
    func oldPreferences() throws {
        let suite = "DEE26.engine.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous: [String: Any] = ["version": 1, "enabled": true, "paused": true,
                                       "excludedIDs": ["excluded"], "promptsEnabled": false]
        defaults.set(try JSONSerialization.data(withJSONObject: previous),
                     forKey: "launcher.suggestions.preferences.v1")
        let store = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(store.engine == .baseline)
        #expect(store.enabled && store.paused)
        #expect(store.excludedIDs == ["excluded"])
        #expect(!store.promptsEnabled)
        #expect(!store.storageUnavailable)
    }

    @Test("In-flight Core ML cannot publish across engine or consent changes", arguments: ["switch", "reset", "pause", "disable"])
    func retiresPendingCoreML(_ action: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = try LauncherSuggestionTestSeed.url()
        let now = Date()
        let context = LauncherSuggestionContext(date: now, foregroundID: "source", modeID: "work")
        var document = LauncherSuggestionDocument()
        document.examples = (0..<1_000).map { _ in
            LauncherSuggestionExample(context: context, targetID: "target", date: now)
        }
        try await LauncherSuggestionsRepository(directory: directory).save(document, sequence: 1)
        let store = LauncherSuggestionsStore(directory: directory, defaults: nil, coreMLSeedURL: seed)
        await store.prepare()
        store.setTuning(.init(minHistory: 0, minSupport: 0, minDays: 0, minAgreement: 0, maxDistance: 20, neighbors: 15))
        store.setEnabled(true)
        store.setEngine(.coreML)
        let pending = Task { await store.predict(context: context) }
        await Task.yield()
        switch action {
        case "switch": store.setEngine(.baseline)
        case "reset": store.reset()
        case "pause": store.setPaused(true)
        default: store.setEnabled(false)
        }
        let result = await pending.value
        if let result, result.generation == store.revision {
            // If the request started only after the mutation, it must use the new state.
            #expect(action == "switch" || action == "reset")
            if action == "switch" { #expect(result.modelVersion == LauncherSuggestionBaseline.version) }
            if action == "reset" { #expect(result.rankedIDs.isEmpty) }
        }
        #expect(!store.engineBusy)
        #expect(!store.engineUnavailable)
        if action == "reset" {
            #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
        } else if action == "switch" {
            #expect(await store.predict(context: context)?.rankedIDs.contains("target") == true)
        } else {
            #expect(await store.predict(context: context) == nil)
        }
        await store.flush()
    }

    @Test("Engine selection persists through reset without changing consent")
    func enginePreference() async throws {
        let suite = "DEE26.engine.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        store.setEnabled(true)
        store.setPaused(true)
        store.exclude(appID: "excluded")
        store.suppressPrompts()
        store.setEngine(.coreML)
        store.reset()
        await store.flush()
        let reloaded = LauncherSuggestionsStore(directory: nil, defaults: defaults)
        #expect(reloaded.engine == .coreML)
        #expect(reloaded.enabled && reloaded.paused)
        #expect(reloaded.excludedIDs == ["excluded"])
        #expect(!reloaded.promptsEnabled)
    }

    @Test("A missing Core ML seed reports unavailable instead of using baseline")
    func unavailableEngine() async throws {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mlmodel")
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil, coreMLSeedURL: absent)
        store.setEnabled(true)
        teach(store)
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        let baseline = try #require(await store.predict(context: context))
        #expect(baseline.rankedIDs.contains("target"))
        store.setEngine(.coreML)
        #expect(store.revision != baseline.generation)
        let unavailable = await store.predict(context: context)
        #expect(unavailable == nil)
        #expect(store.engineUnavailable)
        #expect(!store.storageUnavailable)
        #expect(!store.engineBusy)
        store.setEngine(.baseline)
        let restored = try #require(await store.predict(context: context))
        #expect(restored.rankedIDs.contains("target"))
        #expect(!store.engineUnavailable)
    }

    @Test("Disabled and paused Core ML predictions do not attempt unavailable training")
    func inactiveEngine() async throws {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mlmodel")
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil, coreMLSeedURL: absent)
        store.setEngine(.coreML)
        let context = LauncherSuggestionContext(date: Date(), foregroundID: "source", modeID: nil)
        #expect(await store.predict(context: context) == nil)
        #expect(!store.engineBusy)
        store.setEnabled(true)
        store.setPaused(true)
        #expect(await store.predict(context: context) == nil)
        #expect(!store.engineBusy)
    }

    private func teach(_ store: LauncherSuggestionsStore) {
        store.setTuning(.init(minHistory: 0, minSupport: 0, minDays: 0, minAgreement: 0, maxDistance: 20, neighbors: 15))
        let start = Date().addingTimeInterval(-30)
        store.beginSession(foregroundID: "source", runningIDs: ["source"], now: start)
        store.observeActivation(appID: "target", now: start.addingTimeInterval(10))
        store.settleActivation(now: start.addingTimeInterval(13))
    }
}
