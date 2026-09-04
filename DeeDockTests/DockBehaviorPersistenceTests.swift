import Foundation
import Testing

@MainActor struct DockBehaviorPersistenceTests {
    @Test("Old documents receive behavior defaults, while malformed behavior preserves saved bytes")
    func migration() throws {
        let suite = "DeeDockBehaviorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings())) as? [String: Any])
        old.removeValue(forKey: "behavior")
        old.removeValue(forKey: "showSessionCapsules")
        let legacy = try JSONSerialization.data(withJSONObject: old)
        defaults.set(legacy, forKey: "dock.settings.v1")
        let repository = DockSettingsRepository(defaults: defaults)
        #expect(try repository.load().behavior == DockBehaviorSettings())
        #expect(try repository.load().showSessionCapsules)
        #expect(defaults.data(forKey: "dock.settings.v1") == legacy)
        old["behavior"] = NSNull()
        let malformed = try JSONSerialization.data(withJSONObject: old)
        defaults.set(malformed, forKey: "dock.settings.v1")
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.data(forKey: "dock.settings.v1") == malformed)
    }

    @Test("Behavior inheritance is field-specific; resets preserve independent pins and visibility")
    func inheritance() throws {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let screen = DisplayFixtures.screen("test", runtimeID: 1, primary: true)
        profiles.synchronize([screen]) { [DisplayFixtures.app("pin")] }
        profiles.update(screen.id, keyPath: \.behavior.animationStyle, to: .bounceFade)
        profiles.update(screen.id, keyPath: \.behavior.revealDelay, to: 0.1)
        defaults.update(\.behavior.autoHide, to: true)
        defaults.update(\.behavior.revealDelay, to: 0.5)
        #expect(profiles.effectiveSettings(for: screen.id).behavior.autoHide)
        #expect(profiles.effectiveSettings(for: screen.id).behavior.revealDelay == 0.1)
        #expect(profiles.effectiveSettings(for: screen.id).behavior.animationStyle == .bounceFade)
        profiles.setEnabled(false, for: screen.id)
        defaults.restoreDefaults()
        #expect(profiles.effectiveSettings(for: screen.id).behavior.animationStyle == .bounceFade)
        profiles.useDefault(.animationStyle, for: screen.id)
        #expect(profiles.effectiveSettings(for: screen.id).behavior.animationStyle == .slideFade)
        profiles.useDefaults(for: screen.id)
        #expect(profiles.document.profiles[screen.id]?.enabled == false)
        #expect(profiles.pinLists[screen.id]?.count == 1)
    }

    @Test("All styles persist by stable identifier; timing and dimensions validate and normalize")
    func validation() throws {
        for style in DockAnimationStyle.allCases {
            var settings = DockSettings(); settings.behavior.animationStyle = style
            #expect(try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
        var settings = DockSettings()
        settings.behavior.revealDelay = 0.123
        #expect(settings.normalized?.behavior.revealDelay == 0.1)
        settings.behavior.customLength = .infinity
        #expect(settings.normalized == nil)
        settings.behavior.customLength = 320
        settings.behavior.zoneDepth = 0
        #expect(settings.normalized == nil)
    }
}
