import Foundation
import Testing
@testable import DeeDock

/// The compatibility switches are off for every existing profile and survive a round trip once enabled.
@MainActor
struct WindowPeekCompatibilityTests {
    @Test("Scroll bar suppression stays off for existing settings and round-trips when enabled")
    func neverShowsScrollBars() throws {
        try assertOptInMigration(\.windowPeekNeverShowsScrollBars, key: "windowPeekNeverShowsScrollBars")
    }

    private func assertOptInMigration(_ keyPath: WritableKeyPath<DockSettings, Bool>, key: String) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var settings = DockSettings.defaults
        #expect(!settings[keyPath: keyPath])
        settings[keyPath: keyPath] = true
        let data = try encoder.encode(settings)
        #expect(try decoder.decode(DockSettings.self, from: data)[keyPath: keyPath])
        // Compatibility switches are app-wide: a display profile never overrides them.
        #expect(DockSettingsOverrides().resolving(settings)[keyPath: keyPath])
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: key)
        let migrated = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated[keyPath: keyPath])
        for preset in WindowPeekPreset.allCases {
            var candidate = settings
            preset.apply(to: &candidate)
            // Presets choose looks; they never touch a troubleshooting switch.
            #expect(candidate[keyPath: keyPath])
        }
    }
}
