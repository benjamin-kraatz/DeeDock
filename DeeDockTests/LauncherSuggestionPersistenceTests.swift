import Foundation
import Testing
@testable import DeeDock

/// Coalesced history writes: ordinary changes wait for a quiet period (capped by a maximum wait),
/// while privacy actions and `flush()` reach the disk without waiting.
@MainActor
struct LauncherSuggestionPersistenceTests {
    @Test("Ordinary changes wait for the quiet period, and flush writes them at once")
    func coalescesUntilFlush() async throws {
        let (directory, repository) = try await seededDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await store(directory, delay: .seconds(60), maxWait: .seconds(600))
        observeTransition(store)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await repository.load().events.isEmpty)
        await store.flush()
        let saved = try await repository.load()
        #expect(saved.events.map(\.kind) == [.sessionStart, .launch, .activation])
        #expect(saved.examples.map(\.targetID) == ["target"])
    }

    @Test("The quiet period writes once changes stop")
    func trailingDelayWrites() async throws {
        let (directory, repository) = try await seededDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await store(directory, delay: .milliseconds(20), maxWait: .seconds(600))
        observeTransition(store)
        #expect(await eventually(timeout: .seconds(10)) {
            (try? await repository.load())?.examples.count == 1
        })
        withExtendedLifetime(store) {}
    }

    @Test("The maximum wait bounds how long changes stay unsaved")
    func maximumWaitWrites() async throws {
        let (directory, repository) = try await seededDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await store(directory, delay: .seconds(60), maxWait: .milliseconds(20))
        observeTransition(store)
        #expect(await eventually(timeout: .seconds(10)) {
            (try? await repository.load())?.examples.count == 1
        })
        withExtendedLifetime(store) {}
    }

    @Test("Reset and exclusion reach the disk without waiting for the quiet period", arguments: ["reset", "exclude"])
    func privacyActionsWriteImmediately(_ action: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LauncherSuggestionsRepository(directory: directory)
        let date = Date()
        var history = LauncherSuggestionDocument()
        history.examples = [.init(context: .init(date: date, foregroundID: "source"), targetID: "target", date: date)]
        try await repository.save(history, sequence: 1)
        let store = try await store(directory, delay: .seconds(60), maxWait: .seconds(600))
        if action == "reset" { store.reset() } else { store.exclude(appID: "target") }
        #expect(await eventually(timeout: .seconds(10)) {
            (try? await repository.load())?.examples.isEmpty == true
        })
        withExtendedLifetime(store) {}
    }

    @Test("A reset supersedes changes still waiting for their write")
    func resetBeatsPendingChanges() async throws {
        let (directory, repository) = try await seededDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await store(directory, delay: .seconds(60), maxWait: .seconds(600))
        observeTransition(store)
        store.reset()
        await store.flush()
        let saved = try await repository.load()
        #expect(saved.events.isEmpty && saved.examples.isEmpty)
    }

    /// An empty saved history, so a later load distinguishes "not written yet" from "written".
    private func seededDirectory() async throws -> (URL, LauncherSuggestionsRepository) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = LauncherSuggestionsRepository(directory: directory)
        try await repository.save(LauncherSuggestionDocument(), sequence: 1)
        return (directory, repository)
    }

    private func store(_ directory: URL, delay: Duration, maxWait: Duration) async throws -> LauncherSuggestionsStore {
        let store = LauncherSuggestionsStore(directory: directory, defaults: nil,
                                              coreMLSeedURL: directory.appendingPathComponent("unused-seed.mlmodelc"),
                                              saveDelay: delay, saveMaxWait: maxWait)
        await store.prepare()
        store.setEnabled(true)
        return store
    }

    /// Records a session start, a launch and a settled activation: three events and one example.
    private func observeTransition(_ store: LauncherSuggestionsStore) {
        let start = Date().addingTimeInterval(-30)
        store.beginSession(foregroundID: "source", runningIDs: ["source"], now: start)
        store.observeLaunch(appID: "target", runningIDs: ["source", "target"], now: start.addingTimeInterval(9))
        store.observeActivation(appID: "target", now: start.addingTimeInterval(10))
        store.settleActivation(now: start.addingTimeInterval(13))
    }
}
