import Foundation
import Testing

@MainActor
struct LauncherSuggestionLifecycleTests {
    @Test("Answering or dismissing a feedback prompt starts its cooldown", arguments: [true, false, nil] as [Bool?])
    func promptCooldown(_ useful: Bool?) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        let first = Date().addingTimeInterval(-8 * 86400)
        var document = LauncherSuggestionDocument()
        document.impressions = (0..<10).map { index in
            let date = first.addingTimeInterval(Double(index) * 60)
            return LauncherSuggestionImpression(id: UUID(), date: date, appIDs: ["target"],
                context: LauncherSuggestionContext(date: date, foregroundID: "source", modeID: nil),
                modelVersion: LauncherSuggestionBaseline.version)
        }
        try await repository.save(document, sequence: 1)
        let store = LauncherSuggestionsStore(directory: directory, defaults: nil,
                                              coreMLSeedURL: directory.appendingPathComponent("unused-seed.mlmodelc"))
        await store.prepare()
        store.setEnabled(true)
        try #require(store.shouldPrompt)
        store.answerPrompt(useful)
        #expect(!store.shouldPrompt)
        await store.flush()
        let saved = try await repository.load()
        #expect(saved.promptAnswers.count == 1)
        #expect(saved.feedback.isEmpty)
        let reloaded = LauncherSuggestionsStore(directory: directory, defaults: nil,
                                              coreMLSeedURL: directory.appendingPathComponent("unused-seed.mlmodelc"))
        await reloaded.prepare()
        reloaded.setEnabled(true)
        #expect(!reloaded.shouldPrompt)
    }

    @Test("Off and paused observation cannot create learning examples")
    func inactiveObservation() async throws {
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        let start = Date().addingTimeInterval(-30)
        observeTransition(store, start: start)
        #expect(!store.hasSession)
        #expect(store.capture(foregroundID: "source", modeID: nil) == nil)
        store.setEnabled(true)
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
        store.setPaused(true)
        observeTransition(store, start: start)
        #expect(!store.hasSession)
        #expect(await store.predict(context: context) == nil)
        store.setPaused(false)
        #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
        await store.flush()
    }

    @Test("Pause retires the snapshot while preserving prior learning for resume")
    func pauseRetiresSnapshot() async throws {
        let store = learnedStore()
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        let snapshot = try #require(await store.predict(context: context))
        #expect(snapshot.rankedIDs.contains("target"))
        store.setPaused(true)
        #expect(snapshot.generation != store.revision)
        #expect(await store.predict(context: context) == nil)
        store.feedback(appID: "target", kind: .notNow, snapshot: snapshot)
        store.setPaused(false)
        let resumed = try #require(await store.predict(context: context))
        #expect(resumed.rankedIDs.contains("target"))
        #expect(resumed.generation != snapshot.generation)
    }

    @Test("Reset rejects old feedback and preserves deliberate preferences")
    func resetRetiresLearning() async throws {
        let store = learnedStore()
        store.exclude(appID: "other")
        store.suppressPrompts()
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        let snapshot = try #require(await store.predict(context: context))
        #expect(snapshot.rankedIDs.contains("target"))
        store.reset()
        store.feedback(appID: "target", kind: .useful, snapshot: snapshot)
        store.recordImpression(snapshot: snapshot, appIDs: ["target"])
        #expect(snapshot.generation != store.revision)
        #expect(store.excludedIDs == ["other"])
        #expect(!store.promptsEnabled)
        #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
        await store.flush()
    }

    @Test("Reversing an exclusion cannot resurrect erased learning or stale feedback")
    func exclusionRetiresLearning() async throws {
        let store = learnedStore()
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        let snapshot = try #require(await store.predict(context: context))
        store.exclude(appID: "target")
        #expect(store.excludedIDs.contains("target"))
        // Other candidates keep their frozen presentation; only this app is invalidated.
        #expect(snapshot.generation == store.revision)
        store.feedback(appID: "target", kind: .useful, snapshot: snapshot)
        store.include(appID: "target")
        #expect(store.excludedIDs.isEmpty)
        #expect(!store.canSuggest(appID: "target", snapshot: snapshot))
        #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
    }

    @Test("A meaningful activation uses preceding foreground and mode without target leakage")
    func precedingContext() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var recorder = LauncherSuggestionRecorder()
        recorder.begin(now: start, foregroundID: "source", runningIDs: ["source", "target"])
        recorder.activate("target", now: start.addingTimeInterval(10), modeID: "work")
        let settled1 = recorder.settle(now: start.addingTimeInterval(12.9))
        #expect(settled1 == nil)
        let settled = recorder.settle(now: start.addingTimeInterval(13))
        let example = try #require(settled)
        #expect(example.targetID == "target")
        #expect(example.context.foregroundID == "source")
        #expect(example.context.modeID == "work")
        #expect(example.context.date == start.addingTimeInterval(10))
        #expect(example.context.secondsSinceUse["target"] == nil)
        #expect(example.context.foregroundSeconds == nil)
        let settled2 = recorder.settle(now: start.addingTimeInterval(15))
        #expect(settled2 == nil)
    }

    @Test("Predictions racing reset cannot restore a usable old ranking")
    func concurrentReset() async throws {
        let store = learnedStore()
        let context = try #require(store.capture(foregroundID: "source", modeID: nil))
        let pending = Task { await store.predict(context: context) }
        // Give the prediction its actor turn; ranking may finish before or after reset.
        // Both outcomes must be safe, without depending on a machine-specific sleep.
        await Task.yield()
        store.reset()
        let result = await pending.value
        if let result, result.generation == store.revision {
            #expect(result.rankedIDs.isEmpty)
        }
        #expect(await store.predict(context: context)?.rankedIDs.isEmpty == true)
        await store.flush()
    }

    @Test("Accidental switches, DDock focus, and session gaps discard pending outcomes")
    func canceledOutcomes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var recorder = LauncherSuggestionRecorder()
        recorder.begin(now: start, foregroundID: "source", runningIDs: ["source"])
        recorder.activate("accidental", now: start.addingTimeInterval(10), modeID: nil)
        recorder.activate("source", now: start.addingTimeInterval(11), modeID: nil)
        let settled3 = recorder.settle(now: start.addingTimeInterval(14))
        #expect(settled3 == nil)
        recorder.activate("target", now: start.addingTimeInterval(15), modeID: nil)
        recorder.activate(nil, now: start.addingTimeInterval(16), modeID: nil)
        let settled4 = recorder.settle(now: start.addingTimeInterval(20))
        #expect(settled4 == nil)
        #expect(recorder.foregroundID == "source")
        recorder.activate("target", now: start.addingTimeInterval(21), modeID: nil)
        recorder.stop()
        let settled5 = recorder.settle(now: start.addingTimeInterval(25))
        #expect(settled5 == nil)
    }

    @Test("Launch and termination are context only, and startup activity is not learned")
    func lifecycleIsNotTarget() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var recorder = LauncherSuggestionRecorder()
        recorder.begin(now: start, foregroundID: "source", runningIDs: ["source"])
        recorder.launched("target", running: ["source", "target"])
        let settled6 = recorder.settle(now: start.addingTimeInterval(10))
        #expect(settled6 == nil)
        recorder.terminated("target", now: start.addingTimeInterval(11), running: ["source", "target"])
        #expect(recorder.context(now: start.addingTimeInterval(12), modeID: nil).secondsSinceTermination["target"] == nil)
        recorder.begin(now: start, foregroundID: "source", runningIDs: ["source", "target"])
        recorder.activate("target", now: start.addingTimeInterval(1), modeID: nil)
        let settled7 = recorder.settle(now: start.addingTimeInterval(4))
        #expect(settled7 == nil)
        #expect(recorder.foregroundID == "target")
    }

    private func learnedStore() -> LauncherSuggestionsStore {
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        store.setTuning(.init(minHistory: 0, minSupport: 0, minDays: 0, minAgreement: 0, maxDistance: 20, neighbors: 15))
        store.setEnabled(true)
        observeTransition(store, start: Date().addingTimeInterval(-30))
        return store
    }

    private func observeTransition(_ store: LauncherSuggestionsStore, start: Date) {
        store.beginSession(foregroundID: "source", runningIDs: ["source"], now: start)
        store.observeLaunch(appID: "target", runningIDs: ["source", "target"], now: start.addingTimeInterval(9))
        store.observeActivation(appID: "target", now: start.addingTimeInterval(10))
        store.settleActivation(now: start.addingTimeInterval(13))
    }
}
