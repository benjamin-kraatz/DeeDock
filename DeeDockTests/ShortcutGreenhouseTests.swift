import Foundation
import Testing

@MainActor
struct ShortcutGreenhouseTests {
    private func store(_ suite: String) throws -> (ShortcutGreenhouseStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (ShortcutGreenhouseStore(repository: ShortcutGreenhouseRepository(defaults: defaults)), defaults)
    }

    @Test("Greenhouse chrome stays off until the user opts in")
    func optInDefault() throws {
        let suite = "GreenhouseOptIn.\(UUID().uuidString)"
        let (greenhouse, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        greenhouse.start()
        #expect(greenhouse.isEnabled == false)
        #expect(defaults.data(forKey: ShortcutGreenhouseLimits.storageKey) == nil)
    }

    @Test("Enabling persists; disabling removes the stored document")
    func enablePersistsThenClears() throws {
        let suite = "GreenhousePersist.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ShortcutGreenhouseStore(repository: ShortcutGreenhouseRepository(defaults: defaults))
        first.start()
        first.setEnabled(true)
        #expect(first.isEnabled)
        #expect(defaults.data(forKey: ShortcutGreenhouseLimits.storageKey) != nil)

        let second = ShortcutGreenhouseStore(repository: ShortcutGreenhouseRepository(defaults: defaults))
        second.start()
        #expect(second.isEnabled)

        second.setEnabled(false)
        #expect(second.isEnabled == false)
        #expect(defaults.data(forKey: ShortcutGreenhouseLimits.storageKey) == nil)

        let third = ShortcutGreenhouseStore(repository: ShortcutGreenhouseRepository(defaults: defaults))
        third.start()
        #expect(third.isEnabled == false)
    }

    @Test("Unreadable bytes freeze edits until an explicit reset")
    func corruptDocumentRequiresReset() throws {
        let suite = "GreenhouseCorrupt.\(UUID().uuidString)"
        let (greenhouse, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: ShortcutGreenhouseLimits.storageKey)
        greenhouse.start()
        #expect(greenhouse.requiresReset)
        #expect(greenhouse.isEnabled == false)
        greenhouse.setEnabled(true)
        #expect(greenhouse.isEnabled == false)
        greenhouse.reset()
        #expect(greenhouse.requiresReset == false)
        #expect(greenhouse.isEnabled == false)
        #expect(defaults.data(forKey: ShortcutGreenhouseLimits.storageKey) == nil)
    }

    @Test("Wilt requires a finished listing that does not include the pin")
    func wiltAfterDiscoveryMiss() {
        let id = UUID()
        #expect(ShortcutGreenhouseHealth.resolve(discovered: false, isAvailable: false) == .healthy)
        #expect(ShortcutGreenhouseHealth.resolve(discovered: false, isAvailable: true) == .healthy)
        #expect(ShortcutGreenhouseHealth.resolve(discovered: true, isAvailable: true) == .healthy)
        #expect(ShortcutGreenhouseHealth.resolve(discovered: true, isAvailable: false) == .wilted)

        let tile = ActionTile(id: id, name: "Morning")
        let wilted = ShortcutGreenhousePlant(
            tile: tile,
            status: .idle,
            discovered: true,
            availableIDs: []
        )
        #expect(wilted.health == .wilted)
        #expect(wilted.canWater)

        let healthy = ShortcutGreenhousePlant(
            tile: tile,
            status: .running,
            discovered: true,
            availableIDs: [id]
        )
        #expect(healthy.health == .healthy)
        #expect(healthy.canWater == false)
    }
}
