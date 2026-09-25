import Foundation
import Testing
@testable import DeeDock

@MainActor
struct DockAppBadgeSettingsTests {
    @Test("Badge counts stay off when the key is absent, and an explicit value round-trips")
    func migration() throws {
        var settings = DockSettings.defaults
        #expect(!settings.showAppBadgeCounts)
        settings.showAppBadgeCounts = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DockSettings.self, from: data).showAppBadgeCounts)
        #expect(DockSettingsOverrides().resolving(settings).showAppBadgeCounts)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "showAppBadgeCounts")
        let migrated = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!migrated.showAppBadgeCounts)
        #expect(!DockSettingsOverrides().resolving(migrated).showAppBadgeCounts)
        let stored = Data(#"{"showAppBadgeCounts":true}"#.utf8)
        let ignored = try JSONDecoder().decode(DockSettingsOverrides.self, from: stored)
        #expect(!ignored.resolving(migrated).showAppBadgeCounts)
    }
}
