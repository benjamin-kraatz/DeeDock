import Foundation
import Testing
@testable import DeeDock

/// The retired Dock Modes store folds into the single configuration without changing any dock.
@MainActor
struct DockModesMigrationTests {
    private let primary = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
    private let other = DisplayFixtures.screen("other", runtimeID: 2, x: -1600)
    private let stale = DisplayFixtures.app("stale")
    private let personal = DisplayFixtures.app("personal")
    private let work = DisplayFixtures.app("work")
    private let reference = DisplayFixtures.app("reference")

    @Test("Only the active mode survives, unchanged")
    func activeModeSurvives() throws {
        try withDefaults { defaults in
            try saveLegacyConfiguration(defaults)
            let personalMode = LegacyMode(name: "Personal", appVisibility: .hideRunning, displays: [
                primary.id: .init(pins: [.application(personal)]),
                other.id: .init(pins: [], appVisibility: .collapsePinned)
            ])
            let workMode = LegacyMode(name: "Work", appVisibility: .collapseRunning, displays: [
                primary.id: .init(pins: [.application(work), .application(reference)]),
                other.id: .init(pins: [.application(reference)], appVisibility: .hidePinned)
            ])
            try saveModes(LegacyModes(modes: [personalMode, workMode], activeModeID: workMode.id,
                                      previousModeID: personalMode.id), in: defaults)

            DockModesMigration(defaults: defaults).run()

            let profiles = loadProfiles(defaults)
            #expect(profiles.pinLists[primary.id] == [.application(work), .application(reference)])
            #expect(profiles.pinLists[other.id] == [.application(reference)])
            #expect(profiles.defaults.value.appVisibility == .collapseRunning)
            #expect(profiles.effectiveSettings(for: primary.id).appVisibility == .collapseRunning)
            #expect(profiles.effectiveSettings(for: other.id).appVisibility == .hidePinned)
            #expect(defaults.object(forKey: DockModesMigration.modesKey) == nil)
        }
    }

    @Test("Running again, or again after a quit before cleanup, changes nothing")
    func idempotent() throws {
        try withDefaults { defaults in
            try saveLegacyConfiguration(defaults)
            let mode = LegacyMode(name: "Default", appVisibility: .collapsePinned, displays: [
                primary.id: .init(pins: [.application(work)], appVisibility: .hideRunning)
            ])
            let modes = try JSONEncoder().encode(LegacyModes(modes: [mode], activeModeID: mode.id))
            defaults.set(modes, forKey: DockModesMigration.modesKey)

            DockModesMigration(defaults: defaults).run()
            let migrated = try configuration(defaults)
            #expect(migrated.pins[primary.id] == [.application(work)])
            DockModesMigration(defaults: defaults).run()
            #expect(try configuration(defaults) == migrated)

            // A quit between the writes and the removal leaves the modes key behind.
            defaults.set(modes, forKey: DockModesMigration.modesKey)
            DockModesMigration(defaults: defaults).run()
            #expect(try configuration(defaults) == migrated)
            #expect(defaults.object(forKey: DockModesMigration.modesKey) == nil)
        }
    }

    @Test("Missing, corrupt, or invalid mode data leaves the live configuration intact",
          arguments: [ModesFixture.missing, .corrupt, .unknownActiveMode, .duplicateNames])
    func unusableModesKeepConfiguration(_ fixture: ModesFixture) throws {
        try withDefaults { defaults in
            try saveLegacyConfiguration(defaults)
            let mode = LegacyMode(name: "Work", appVisibility: .hidePinned, displays: [
                primary.id: .init(pins: [.application(work)])
            ])
            switch fixture {
            case .missing: break
            case .corrupt: defaults.set(Data("corrupt".utf8), forKey: DockModesMigration.modesKey)
            case .unknownActiveMode: try saveModes(LegacyModes(modes: [mode], activeModeID: UUID()), in: defaults)
            case .duplicateNames:
                let copy = LegacyMode(name: " work ", appVisibility: .showAll, displays: [:])
                try saveModes(LegacyModes(modes: [mode, copy], activeModeID: mode.id), in: defaults)
            }
            let before = try configuration(defaults)

            DockModesMigration(defaults: defaults).run()

            #expect(try configuration(defaults) == before)
            #expect(defaults.object(forKey: DockModesMigration.modesKey) == nil)
            let profiles = loadProfiles(defaults)
            #expect(profiles.pinLists[primary.id] == [.application(stale)])
            #expect(profiles.pinLists[other.id] == [.application(reference)])
            #expect(profiles.effectiveSettings(for: primary.id).appVisibility == .collapsePinned)
            #expect(profiles.effectiveSettings(for: other.id).appVisibility == .hideRunning)
        }
    }

    @Test("Per-display overrides stay with their display and only visibility comes from the mode")
    func perDisplayOverrides() throws {
        try withDefaults { defaults in
            try saveLegacyConfiguration(defaults)
            let mode = LegacyMode(name: "Default", appVisibility: .showAll, displays: [
                // The primary display had no override in the mode, so its stale one must go.
                primary.id: .init(pins: [.application(work)]),
                other.id: .init(pins: [.application(personal)], appVisibility: .collapseRunning)
            ])
            try saveModes(LegacyModes(modes: [mode], activeModeID: mode.id), in: defaults)

            DockModesMigration(defaults: defaults).run()

            let document = try DisplayProfilesRepository(defaults: defaults).load()
            #expect(document.initialPrimaryID == primary.id)
            #expect(document.profiles[primary.id]?.overrides.appVisibility == nil)
            #expect(document.profiles[other.id]?.overrides.appVisibility == .collapseRunning)
            #expect(document.profiles[other.id]?.overrides.iconSize == 64)
            #expect(document.profiles[other.id]?.overrides.edge == .left)
            #expect(document.profiles[other.id]?.enabled == false)

            // Reconnecting in a different order, with the other display now primary, keeps each
            // display's configuration with its identity rather than its position.
            let swappedPrimary = DisplayFixtures.screen("other", runtimeID: 7, primary: true)
            let swappedOther = DisplayFixtures.screen("primary", runtimeID: 8, x: 1600)
            let profiles = loadProfiles(defaults, displays: [swappedOther, swappedPrimary])
            #expect(profiles.pinLists[other.id] == [.application(personal)])
            #expect(profiles.pinLists[primary.id] == [.application(work)])
            let otherSettings = profiles.effectiveSettings(for: other.id)
            #expect(otherSettings.appVisibility == .collapseRunning)
            #expect(otherSettings.iconSize == 64)
            #expect(otherSettings.edge == .left)
            #expect(profiles.effectiveSettings(for: primary.id).appVisibility == .showAll)
            #expect(profiles.effectiveSettings(for: primary.id).iconSize == DockSettings.defaults.iconSize)
        }
    }

    // MARK: - Fixtures

    enum ModesFixture: CaseIterable, Sendable {
        case missing, corrupt, unknownActiveMode, duplicateNames
    }

    /// The pre-modes keys, frozen at values that differ from every mode in these tests.
    private func saveLegacyConfiguration(_ defaults: UserDefaults) throws {
        var settings = DockSettings.defaults
        settings.appVisibility = .collapsePinned
        try DockSettingsRepository(defaults: defaults).save(settings)
        let repository = DisplayProfilesRepository(defaults: defaults)
        var otherOverrides = DockSettingsOverrides(appVisibility: .hideRunning)
        otherOverrides.iconSize = 64
        otherOverrides.edge = .left
        try repository.save(DisplayProfilesDocument(initialPrimaryID: primary.id, profiles: [
            primary.id: DisplayProfile(id: primary.id, name: primary.name),
            other.id: DisplayProfile(id: other.id, name: other.name, enabled: false, overrides: otherOverrides)
        ]))
        try repository.savePins([.application(stale)], for: primary.id)
        try repository.savePins([.application(reference)], for: other.id)
    }

    private func saveModes(_ modes: LegacyModes, in defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(modes), forKey: DockModesMigration.modesKey)
    }

    private func loadProfiles(_ defaults: UserDefaults, displays: [DisplaySnapshot]? = nil) -> DisplayProfilesStore {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: DockSettingsRepository(defaults: defaults)),
                                            repository: DisplayProfilesRepository(defaults: defaults))
        profiles.synchronize(displays ?? [other, primary]) { [] }
        return profiles
    }

    /// Decoded values rather than bytes: JSON key order is not guaranteed between encodes.
    private struct Configuration: Equatable {
        var settings: DockSettings
        var profiles: DisplayProfilesDocument
        var pins: [String: [DockPin]]
    }

    private func configuration(_ defaults: UserDefaults) throws -> Configuration {
        var pins: [String: [DockPin]] = [:]
        for id in [primary.id, other.id] {
            pins[id] = try DockPinsRepository(defaults: defaults, displayID: id).load()
        }
        return Configuration(settings: try DockSettingsRepository(defaults: defaults).load(),
                             profiles: try DisplayProfilesRepository(defaults: defaults).load(), pins: pins)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "DockModesMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

/// The `dock.modes.v1` shape the retired store wrote. Recipes are omitted, as an empty one was.
private struct LegacyModes: Encodable {
    var version = 1
    var modes: [LegacyMode]
    var activeModeID: UUID
    var previousModeID: UUID?
}

private struct LegacyMode: Encodable {
    struct Display: Encodable {
        var pins: [DockPin]
        var appVisibility: DockAppVisibility?
    }

    var id = UUID()
    var name: String
    var appVisibility: DockAppVisibility
    var displays: [String: Display]
}
