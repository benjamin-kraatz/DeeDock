import Foundation
import Testing
@testable import DeeDock

/// The compatibility switches keep their defaults for existing profiles and survive a round trip once changed.
@MainActor
struct WindowPeekCompatibilityTests {
    @Test("Scroll bar suppression is on for existing settings and round-trips when disabled")
    func neverShowsScrollBars() throws {
        try assertMigration(\.windowPeekNeverShowsScrollBars, key: "windowPeekNeverShowsScrollBars", default: true)
    }

    @Test("Fixed panel size is on for existing settings and round-trips when disabled")
    func keepsPanelSize() throws {
        try assertMigration(\.windowPeekKeepsPanelSize, key: "windowPeekKeepsPanelSize", default: true)
    }

    @Test("Automatic capture resolution stays off for existing settings and round-trips when enabled")
    func capturesAtAutomaticResolution() throws {
        try assertMigration(\.windowPeekCapturesAtAutomaticResolution,
                            key: "windowPeekCapturesAtAutomaticResolution", default: false)
    }

    private func assertMigration(_ keyPath: WritableKeyPath<DockSettings, Bool>, key: String,
                                 default defaultValue: Bool) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var settings = DockSettings.defaults
        #expect(settings[keyPath: keyPath] == defaultValue)
        settings[keyPath: keyPath] = !defaultValue
        let data = try encoder.encode(settings)
        #expect(try decoder.decode(DockSettings.self, from: data)[keyPath: keyPath] == !defaultValue)
        // Compatibility switches are app-wide: a display profile never overrides them.
        #expect(DockSettingsOverrides().resolving(settings)[keyPath: keyPath] == !defaultValue)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: key)
        let migrated = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated[keyPath: keyPath] == defaultValue)
        for preset in WindowPeekPreset.allCases {
            var candidate = settings
            preset.apply(to: &candidate)
            // Presets choose looks; they never touch a troubleshooting switch.
            #expect(candidate[keyPath: keyPath] == !defaultValue)
        }
    }
}
