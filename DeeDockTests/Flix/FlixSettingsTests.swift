import Foundation
import Testing
@testable import DeeDock

/// Flix Files' settings persist as JSON under `flix.settings.v1`, in a throwaway defaults suite here.
struct FlixSettingsTests {
    private let suite = "dokk.tests.flix.\(UUID().uuidString)"

    private func repository() -> (FlixSettingsRepository, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (FlixSettingsRepository(defaults: defaults), defaults)
    }

    @Test func defaultsMatchTheLockedDecisions() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = try repository.load()
        #expect(settings == FlixSettings())
        #expect(settings.isEnabled && settings.showsDockTile)
        #expect(!settings.showsMenuBarItem)
        #expect(settings.shortcutEnabled && settings.shortcut == .default)
        #expect(settings.shortcut.modifiers == [.control, .option, .command])
        #expect(!settings.tracksLinks && !settings.tracksPagesYouRead && !settings.fetchesSiteIcons)
        #expect(settings.excludesSensitiveSites)
        #expect(settings.onOpen == .nothing && settings.afterDrag == .close)
        #expect(settings.watchedFolders.count == 4)
        #expect(settings.watchedFolders.allSatisfy { $0.isEnabled && $0.access == .unknown })
    }

    @Test func settingsRoundTrip() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = FlixSettings()
        settings.showsMenuBarItem = true
        settings.shortcut = FlixShortcutCombo(keyCode: 49, modifiers: [.control, .command])
        settings.onOpen = .copyNewestPath
        settings.afterDrag = .stayOpen
        settings.tracksLinks = true
        settings.excludedSites = ["bank.example.com"]
        settings.watchedFolders = [FlixWatchedFolder(path: "/tmp/watch/", access: .allowed)]
        settings.learnsDragDestinations = false
        try repository.save(settings)
        #expect(FlixSettingsRepository.key == "flix.settings.v1")
        #expect(defaults.data(forKey: FlixSettingsRepository.key) != nil)
        let loaded = try repository.load()
        #expect(loaded == settings)
        #expect(loaded.watchedFolders.first?.path == "/tmp/watch")
    }

    @Test func missingKeysTakeTheirDefaults() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"showsDockTile":false,"tracksLinks":true}"#.utf8), forKey: FlixSettingsRepository.key)
        let settings = try repository.load()
        #expect(!settings.showsDockTile && settings.tracksLinks)
        #expect(settings.isEnabled && !settings.showsMenuBarItem && settings.shortcut == .default)
        #expect(settings.watchedFolders == FlixSettings().watchedFolders)
    }

    @Test func anUnknownEnumValueFallsBackInsteadOfFailing() throws {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"onOpen":"teleport","afterDrag":"stayOpen"}"#.utf8), forKey: FlixSettingsRepository.key)
        let settings = try repository.load()
        #expect(settings.onOpen == .nothing)
        #expect(settings.afterDrag == .stayOpen)
    }

    @Test func unreadableDataFallsBackToDefaults() {
        let (repository, defaults) = repository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not data", forKey: FlixSettingsRepository.key)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(repository.loadOrDefault() == FlixSettings())
    }

    @MainActor @Test func storeUpdatesOneFolderAccess() {
        let store = FlixSettingsStore(repository: nil)
        var changes = 0
        store.changed = { _, _ in changes += 1 }
        let path = store.settings.watchedFolders[2].path
        store.setAccess(.allowed, for: path)
        store.setAccess(.allowed, for: path)
        #expect(store.settings.watchedFolders[2].access == .allowed)
        #expect(changes == 1)
        store.addWatchedFolder("/tmp/projects/", access: .allowed)
        #expect(store.settings.watchedFolders.last?.path == "/tmp/projects")
        store.removeWatchedFolder("/tmp/projects")
        #expect(!store.settings.watchedFolders.contains { $0.path == "/tmp/projects" })
    }
}
