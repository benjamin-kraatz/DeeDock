import Foundation
import Testing
@testable import DeeDock

@MainActor
struct WindowWatchPresetTests {
    private func defaults(_ name: String = UUID().uuidString) throws -> (UserDefaults, String) {
        let suite = "WatchPresets.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeStore(_ defaults: UserDefaults) -> WindowWatchPresetStore {
        let store = WindowWatchPresetStore(repository: WindowWatchPresetRepository(defaults: defaults))
        store.start()
        return store
    }

    private func preset(name: String = "Export done", bundle: String? = "com.apple.dt.Xcode",
                        appName: String = "Xcode", phrase: String = "Export complete",
                        completion: WindowWatchCompletionAction = .none) -> WindowWatchPreset {
        WindowWatchPreset(
            id: UUID(),
            name: name,
            configuration: WindowWatchPresetConfiguration(
                region: NormalizedWindowRegion(x: 0.1, y: 0.2, width: 0.4, height: 0.3),
                usesPhrase: !phrase.isEmpty,
                phrase: phrase,
                playSound: true,
                completion: completion,
                appHint: WindowWatchAppHint(bundleIdentifier: bundle, appName: appName, title: "Export")
            ).normalized(),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    @Test("A saved preset survives a restart and never stores a window ID")
    func persistence() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeStore(defaults)
        let saved = try first.save(preset())
        #expect(saved.configuration.appHint?.title == "Export")

        let reloaded = makeStore(defaults)
        #expect(reloaded.presets.map(\.id) == [saved.id])
        #expect(reloaded.presets[0].name == "Export done")
        #expect(reloaded.presets[0].configuration.phrase == "Export complete")
        #expect(reloaded.presets[0].configuration.region == NormalizedWindowRegion(x: 0.1, y: 0.2, width: 0.4, height: 0.3))
        let encoded = try #require(defaults.data(forKey: "dock.window-watch-presets.v1"))
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("windowID"))
        #expect(!json.contains("processIdentifier"))
    }

    @Test("Unreadable storage is reported and never overwritten")
    func corruptData() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("not presets".utf8)
        defaults.set(bytes, forKey: "dock.window-watch-presets.v1")

        let repository = WindowWatchPresetRepository(defaults: defaults)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.data(forKey: "dock.window-watch-presets.v1") == bytes)

        let store = makeStore(defaults)
        #expect(store.requiresReset)
        #expect(store.error != nil)
        #expect(throws: (any Error).self) { try store.save(preset()) }
        #expect(defaults.data(forKey: "dock.window-watch-presets.v1") == bytes)

        try store.reset()
        #expect(!store.requiresReset)
        #expect(defaults.data(forKey: "dock.window-watch-presets.v1") != bytes)
    }

    @Test("An unknown document version fails rather than reading as an empty list")
    func versionGuard() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data(#"{"version":99,"presets":[]}"#.utf8)
        defaults.set(bytes, forKey: "dock.window-watch-presets.v1")
        #expect(throws: (any Error).self) { try WindowWatchPresetRepository(defaults: defaults).load() }
        #expect(defaults.data(forKey: "dock.window-watch-presets.v1") == bytes)
    }

    @Test("Empty names, empty phrases, and a 31st preset are rejected")
    func validation() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)
        var unnamed = preset()
        unnamed.name = "   "
        #expect(throws: (any Error).self) { try store.save(unnamed) }

        var silentPhrase = preset(phrase: "")
        silentPhrase.configuration.usesPhrase = true
        #expect(throws: (any Error).self) { try store.save(silentPhrase) }

        for index in 0..<WindowWatchPresetDocument.capacity {
            try store.save(preset(name: "Watch \(index)", phrase: "Done \(index)"))
        }
        #expect(throws: (any Error).self) { try store.save(preset(name: "Overflow")) }
        #expect(store.presets.count == WindowWatchPresetDocument.capacity)
    }

    @Test("Duplicate assigns a new identity; delete removes only that preset")
    func duplicateAndDelete() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)
        let original = try store.save(preset())
        let copy = try store.duplicate(original.id)
        #expect(copy.id != original.id)
        #expect(store.presets.count == 2)
        try store.delete(original.id)
        #expect(store.presets.map(\.id) == [copy.id])
        #expect(store.preset(original.id) == nil)
    }

    @Test("A run snapshot keeps its configuration after the saved preset is edited or deleted")
    func snapshotIndependence() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)
        let saved = try store.save(preset())
        let snapshot = WindowWatchRunSnapshot(runID: UUID(), presetID: saved.id, presetName: saved.name,
                                              configuration: saved.configuration)
        var edited = saved
        edited.configuration.phrase = "Something else"
        edited.configuration.playSound = false
        try store.save(edited)
        #expect(store.preset(saved.id)?.configuration != snapshot.configuration)
        try store.delete(saved.id)
        #expect(store.preset(saved.id) == nil)
        #expect(snapshot.configuration.phrase == "Export complete")
        #expect(snapshot.configuration.playSound)
    }

    @Test("App hints suggest candidates and never resolve a window by themselves")
    func suggestionMatching() throws {
        let xcode = preset(bundle: "com.apple.dt.Xcode")
        let preview = preset(name: "Preview", bundle: "com.apple.Preview", appName: "Preview", phrase: "Saved")
        #expect(xcode.matching(bundleIdentifier: "com.apple.dt.Xcode", appName: "Xcode"))
        #expect(!xcode.matching(bundleIdentifier: "com.apple.Preview", appName: "Preview"))
        #expect(preview.matching(bundleIdentifier: nil, appName: "Preview"))
        #expect(!preview.matching(bundleIdentifier: nil, appName: "Mail"))
    }

    @Test("Only a detected run can begin a completion action, and a run identity is required")
    func actionGate() {
        let action = WindowWatchCompletionAction.runShortcut(id: UUID(), name: "Notify")
        let run = UUID()
        // `begin` mutates the gate, and `#expect` captures its argument immutably, so each call runs first.
        var gate = WindowWatchActionGate(runID: run, outcome: .watching, action: action)
        #expect(!gate.canOffer)
        let began1 = gate.begin(run)
        #expect(!began1)

        gate.outcome = .cancelled
        #expect(!gate.canOffer)
        let began2 = gate.begin(run)
        #expect(!began2)

        gate.outcome = .failed
        #expect(!gate.canOffer)
        let began3 = gate.begin(run)
        #expect(!began3)

        gate.outcome = .detected
        #expect(gate.canOffer)
        let began4 = gate.begin(UUID())
        #expect(!began4)
        let began5 = gate.begin(run)
        #expect(began5)
        #expect(gate.phase == .running)
        #expect(!gate.canOffer)
        let began6 = gate.begin(run)
        #expect(!began6)

        gate.finish(success: false)
        #expect(gate.phase == .failed)
        #expect(gate.canOffer)
        let began7 = gate.begin(run)
        #expect(began7)
        gate.finish(success: true)
        #expect(gate.phase == .succeeded)
        #expect(!gate.canOffer)
        let began8 = gate.begin(run)
        #expect(!began8)
    }
}
