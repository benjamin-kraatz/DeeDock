import Foundation
import Testing

@MainActor
struct DockSettingsTests {
    @Test("Defaults preserve existing appearance and prefer usable desktop space")
    func defaults() {
        let settings = DockSettings.defaults
        #expect(settings.iconSize == 48)
        #expect(settings.magnification == 1.4)
        #expect(settings.positionReference == .usableDesktop)
        #expect(settings.alignment == .center)
        #expect(settings.alongEdgeOffset == 0)
        #expect(settings.edgeDistance == 8)
    }

    @Test("Invalid numeric values cannot reach geometry or persistence")
    func validation() {
        for invalid in [Double.nan, .infinity, -.infinity, 31, 97] {
            var settings = DockSettings.defaults
            settings.iconSize = invalid
            #expect(settings.normalized == nil)
        }
        var settings = DockSettings.defaults
        settings.magnification = 2.1
        #expect(settings.normalized == nil)
        settings = .defaults
        settings.alongEdgeOffset = -1001
        #expect(settings.normalized == nil)
        settings = .defaults
        settings.edgeDistance = -1
        #expect(settings.normalized == nil)
        settings = .defaults
        settings.iconSize = 63.6
        settings.magnification = 1.47
        #expect(settings.normalized?.iconSize == 64)
        #expect(settings.normalized?.magnification == 1.45)
    }

    @Test("Settings round-trip and reset without changing pins")
    func persistenceAndReset() throws {
        let suite = "DeeDockSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = DockSettingsRepository(defaults: defaults)
        #expect(try repository.load() == .defaults)
        #expect(defaults.object(forKey: "dock.settings.v1") == nil)
        let pins = FavoritesRepository(defaults: defaults)
        let app = ApplicationReference(bundleIdentifier: "sample.app", url: URL(fileURLWithPath: "/Sample.app"), name: "Sample")
        try pins.save([app])
        var custom = DockSettings.defaults
        custom.iconSize = 96
        custom.magnification = 2
        custom.positionReference = .screenEdge
        custom.alignment = .end
        custom.alongEdgeOffset = -150
        custom.edgeDistance = 40
        try repository.save(custom)
        #expect(try DockSettingsRepository(defaults: defaults).load() == custom)
        try repository.save(.defaults)
        #expect(try repository.load() == .defaults)
        #expect(try pins.load { [] } == [app])
    }

    @Test("Corrupt and out-of-range saved settings are surfaced without replacement")
    func corruptData() throws {
        let suite = "DeeDockSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = DockSettingsRepository(defaults: defaults)
        var invalid = DockSettings.defaults
        invalid.iconSize = 500
        for data in [Data("broken".utf8), try JSONEncoder().encode(invalid)] {
            defaults.set(data, forKey: "dock.settings.v1")
            #expect(throws: (any Error).self) { try repository.load() }
            #expect(defaults.data(forKey: "dock.settings.v1") == data)
            #expect(throws: (any Error).self) { try repository.save(invalid) }
            #expect(defaults.data(forKey: "dock.settings.v1") == data)
        }
        defaults.set("wrong type", forKey: "dock.settings.v1")
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.string(forKey: "dock.settings.v1") == "wrong type")
    }
}
