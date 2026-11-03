import Foundation
import Testing
@testable import DeeDock

/// The retired Atmosphere's preferences are removed once, and nothing beside them is touched.
struct AtmosphereCleanupTests {
    @Test("Removes both Atmosphere keys, leaves other preferences, and runs once")
    func removesOnlyAtmosphere() throws {
        try withDefaults { defaults in
            defaults.set(Data("{}".utf8), forKey: "atmosphere.settings.v1")
            defaults.set(Data("png".utf8), forKey: "atmosphere.decor.v1")
            // A neighbouring key with a similar name must survive.
            defaults.set(true, forKey: "atmosphere.settings.v2")
            defaults.set(Data("dock".utf8), forKey: "dock.settings.v1")

            AtmosphereCleanup(defaults: defaults).run()

            #expect(defaults.object(forKey: "atmosphere.settings.v1") == nil)
            #expect(defaults.object(forKey: "atmosphere.decor.v1") == nil)
            #expect(defaults.bool(forKey: "atmosphere.settings.v2"))
            #expect(defaults.data(forKey: "dock.settings.v1") == Data("dock".utf8))
            #expect(defaults.bool(forKey: AtmosphereCleanup.completedKey))

            // Keys that reappear, say from a restored backup, are left for the person.
            defaults.set(Data("{}".utf8), forKey: "atmosphere.settings.v1")
            AtmosphereCleanup(defaults: defaults).run()
            #expect(defaults.data(forKey: "atmosphere.settings.v1") == Data("{}".utf8))
        }
    }

    @Test("A Mac that never used Atmosphere completes without errors")
    func nothingToRemove() throws {
        try withDefaults { defaults in
            AtmosphereCleanup(defaults: defaults).run()
            #expect(defaults.bool(forKey: AtmosphereCleanup.completedKey))
            #expect(AtmosphereCleanup.removedKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "atmosphere.cleanup.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
