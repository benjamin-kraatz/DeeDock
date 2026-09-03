import Foundation
import Testing

@MainActor
struct DisplayProfilesTests {
    @Test("An empty primary seeds empty pins and changing primary never moves profiles")
    func emptyPrimaryAndRearrangement() throws {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let first = DisplayFixtures.screen("first", runtimeID: 1, primary: true)
        let second = DisplayFixtures.screen("second", runtimeID: 2, x: -1600)
        profiles.synchronize([first]) { [DisplayFixtures.app("starter")] }
        try profiles.savePins([], for: first.id)
        profiles.synchronize([second, first]) { [DisplayFixtures.app("must-not-seed")] }
        #expect(profiles.pinLists[second.id] == [])
        try profiles.savePins([DisplayFixtures.app("local")], for: second.id)
        profiles.update(second.id, keyPath: \.iconSize, to: 72)
        let formerPrimary = DisplayFixtures.screen("first", runtimeID: 1, x: -1600)
        let newPrimary = DisplayFixtures.screen("second", runtimeID: 2, primary: true)
        profiles.synchronize([formerPrimary, newPrimary]) { [] }
        #expect(profiles.pinLists[first.id] == [])
        #expect(profiles.pinLists[second.id] == [DisplayFixtures.app("local")])
        #expect(profiles.effectiveSettings(for: second.id).iconSize == 72)
        #expect(profiles.effectiveSettings(for: first.id).iconSize == 48)
    }

    @Test("Legacy pins migrate once; new displays copy the current primary and remain independent")
    func migration() throws {
        let suite = "DeeDockProfilesTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = DisplayFixtures.app("original")
        try FavoritesRepository(defaults: preferences).save([original])
        var appearance = DockSettings.defaults
        appearance.iconSize = 72
        try DockSettingsRepository(defaults: preferences).save(appearance)
        let defaults = DockSettingsStore(repository: DockSettingsRepository(defaults: preferences))
        let repository = DisplayProfilesRepository(defaults: preferences)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: repository)
        let primary = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let other = DisplayFixtures.screen("other", runtimeID: 2, x: -1600)
        profiles.synchronize([other, primary]) { [DisplayFixtures.app("seed")] }
        #expect(profiles.pinLists[primary.id] == [original])
        #expect(profiles.pinLists[other.id] == [original])
        #expect(profiles.effectiveSettings(for: other.id).iconSize == 72)
        try profiles.savePins([], for: other.id)
        try profiles.savePins([DisplayFixtures.app("changed")], for: primary.id)
        profiles.synchronize([primary]) { [] }
        #expect(profiles.remembered.map(\.id) == [other.id])
        let new = DisplayFixtures.screen("new", runtimeID: 3)
        profiles.synchronize([other, new, primary]) { [] }
        #expect(profiles.pinLists[other.id] == [])
        #expect(profiles.pinLists[new.id] == profiles.pinLists[primary.id])
        let restarted = DisplayProfilesStore(defaults: defaults, repository: repository)
        restarted.synchronize([other, primary, new]) { [] }
        #expect(restarted.pinLists[other.id] == [])
        #expect(try FavoritesRepository(defaults: preferences).load { [] } == [original])
    }

    @Test("Overrides inherit per field; resets preserve visibility and pins, including offline edits")
    func overrides() throws {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let display = DisplayFixtures.screen("test", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { [DisplayFixtures.app("pin")] }
        profiles.update(display.id, keyPath: \.iconSize, to: 48) // Explicit, even though equal to the default.
        defaults.update(\.iconSize, to: 80)
        defaults.update(\.edgeDistance, to: 40)
        #expect(profiles.effectiveSettings(for: display.id).iconSize == 48)
        #expect(profiles.effectiveSettings(for: display.id).edgeDistance == 40)
        profiles.setEnabled(false, for: display.id)
        profiles.synchronize([]) { [] }
        profiles.update(display.id, keyPath: \.magnification, to: 2)
        defaults.restoreDefaults()
        #expect(profiles.effectiveSettings(for: display.id).magnification == 2)
        profiles.useDefault(.iconSize, for: display.id)
        #expect(profiles.document.profiles[display.id]?.overrides.iconSize == nil)
        profiles.useDefaults(for: display.id)
        #expect(profiles.effectiveSettings(for: display.id) == .defaults)
        #expect(profiles.document.profiles[display.id]?.enabled == false)
        #expect(profiles.pinLists[display.id] == [DisplayFixtures.app("pin")])
    }

    @Test("Interrupted migration resumes and corrupt pins or profiles are never overwritten")
    func interruptedAndCorrupt() throws {
        let suite = "DeeDockProfilesTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let repository = DisplayProfilesRepository(defaults: preferences)
        try repository.save(DisplayProfilesDocument(initialPrimaryID: display.id,
                                                    profiles: [display.id: DisplayProfile(id: display.id, name: display.name)]))
        try FavoritesRepository(defaults: preferences).save([])
        let defaults = DockSettingsStore(repository: nil)
        let resumed = DisplayProfilesStore(defaults: defaults, repository: repository)
        resumed.synchronize([display]) { [DisplayFixtures.app("must-not-seed")] }
        #expect(resumed.pinLists[display.id] == [])
        let bad = Data("bad".utf8)
        preferences.set(bad, forKey: "dock.favorites.v2.\(display.id)")
        let corrupt = DisplayProfilesStore(defaults: defaults, repository: repository)
        corrupt.synchronize([display]) { [] }
        #expect(corrupt.pinErrors[display.id] != nil)
        #expect(throws: (any Error).self) { try corrupt.savePins([], for: display.id) }
        #expect(preferences.data(forKey: "dock.favorites.v2.\(display.id)") == bad)
        preferences.set(bad, forKey: "dock.displays.v1")
        let blocked = DisplayProfilesStore(defaults: defaults, repository: repository)
        blocked.synchronize([display]) { [] }
        blocked.useDefaults(for: display.id)
        #expect(blocked.requiresReset)
        #expect(preferences.data(forKey: "dock.displays.v1") == bad)
    }

    @Test("Ambiguous identity uses session-only pins and never replaces a saved profile")
    func sessionOnly() throws {
        let suite = "DeeDockProfilesTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let repository = DisplayProfilesRepository(defaults: preferences)
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: repository)
        let display = DisplayFixtures.screen("ambiguous", runtimeID: 1, primary: true, persistent: false)
        profiles.synchronize([display]) { [] }
        profiles.update(display.id, keyPath: \.iconSize, to: 80)
        try profiles.savePins([DisplayFixtures.app("temporary")], for: display.id)
        #expect(try repository.load().profiles.isEmpty)
        #expect(try repository.existingPins(for: display.id) == nil)
        profiles.synchronize([]) { [] }
        #expect(profiles.document.profiles[display.id] == nil)
    }
}
