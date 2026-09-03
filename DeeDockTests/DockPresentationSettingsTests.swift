import Foundation
import Testing

@MainActor
struct DockPresentationSettingsTests {
    @Test("Absent keys preserve legacy appearance and explicit values round-trip")
    func persistence() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder.encode(DockSettings.defaults)) as? [String: Any])
        legacy.removeValue(forKey: "appVisibility"); legacy.removeValue(forKey: "tooltipPreset")
        let decoded = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.appVisibility == .showAll && decoded.tooltipPreset == .classic)
        for mode in DockAppVisibility.allCases {
            for preset in DockTooltipPreset.allCases {
                var settings = decoded; settings.appVisibility = mode; settings.tooltipPreset = preset
                #expect(try decoder.decode(DockSettings.self, from: encoder.encode(settings)) == settings)
                #expect(settings.normalized == settings)
            }
        }
        for key in ["appVisibility", "tooltipPreset"] {
            for invalid in ["unknown" as Any, NSNull(), 3] {
                var malformed = legacy; malformed[key] = invalid
                let data = try JSONSerialization.data(withJSONObject: malformed)
                #expect(throws: (any Error).self) { try decoder.decode(DockSettings.self, from: data) }
            }
        }
    }

    @Test("Display overrides keep explicit Show all and Off distinct from inheritance")
    func overrides() throws {
        var defaults = DockSettings.defaults
        defaults.appVisibility = .hidePinned; defaults.tooltipPreset = .spectrum
        var overrides = DockSettingsOverrides()
        #expect(overrides.resolving(defaults).appVisibility == .hidePinned)
        var explicit = defaults; explicit.appVisibility = .showAll; explicit.tooltipPreset = .off
        overrides.set(.appVisibility, from: explicit); overrides.set(.tooltipPreset, from: explicit)
        let restored = try JSONDecoder().decode(DockSettingsOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(restored.contains(.appVisibility) && restored.contains(.tooltipPreset))
        #expect(restored.resolving(defaults).appVisibility == .showAll)
        #expect(restored.resolving(defaults).tooltipPreset == .off)
        overrides.set(.appVisibility, from: nil); overrides.set(.tooltipPreset, from: nil)
        #expect(overrides.resolving(defaults) == defaults)
        #expect(!overrides.contains(.appVisibility) && !overrides.contains(.tooltipPreset))
        for data in [Data(#"{"appVisibility":"unknown"}"#.utf8), Data(#"{"tooltipPreset":"unknown"}"#.utf8)] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(DockSettingsOverrides.self, from: data) }
        }
    }

    @Test("Remembered displays persist independently and reset without altering pins")
    func profiles() throws {
        let name = "DockPresentationSettingsTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let settings = DockSettingsStore(repository: DockSettingsRepository(defaults: preferences))
        let repository = DisplayProfilesRepository(defaults: preferences)
        let profiles = DisplayProfilesStore(defaults: settings, repository: repository)
        let screens = [DisplayFixtures.screen("one", runtimeID: 1, primary: true), DisplayFixtures.screen("two", runtimeID: 2)]
        let pin = DisplayFixtures.app("sample")
        profiles.synchronize(screens, starterPins: { [pin] })
        profiles.update(screens[0].id, keyPath: \.appVisibility, to: .collapsePinned)
        profiles.update(screens[0].id, keyPath: \.tooltipPreset, to: .off)
        profiles.update(screens[1].id, keyPath: \.appVisibility, to: .hideRunning)
        profiles.synchronize([screens[0]], starterPins: { [] })
        profiles.update(screens[1].id, keyPath: \.tooltipPreset, to: .pop)
        let restored = DisplayProfilesStore(defaults: settings, repository: repository)
        restored.synchronize(screens, starterPins: { [] })
        #expect(restored.effectiveSettings(for: screens[0].id).appVisibility == .collapsePinned)
        #expect(restored.effectiveSettings(for: screens[1].id).appVisibility == .hideRunning)
        #expect(restored.effectiveSettings(for: screens[1].id).tooltipPreset == .pop)
        restored.useDefaults(for: screens[0].id)
        #expect(restored.effectiveSettings(for: screens[0].id).appVisibility == .showAll)
        #expect(restored.pinLists[screens[0].id] == [pin])
        #expect(restored.pinLists[screens[1].id] == [pin])
    }
}
