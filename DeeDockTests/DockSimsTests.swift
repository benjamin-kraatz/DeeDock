import Foundation
import Testing

@MainActor
struct DockSimsTests {
    private func store(_ suite: String) throws -> (DockSimsStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (DockSimsStore(repository: DockSimsRepository(defaults: defaults)), defaults)
    }

    @Test("Moods stay hidden until the user opts in")
    func optInDefault() throws {
        let suite = "SimsOptIn.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        sims.start()
        #expect(sims.isEnabled == false)
        #expect(sims.pinState(for: "safari", isFavorite: true) == nil)
        sims.care(.feed, pinID: "safari")
        #expect(sims.hasPets == false)
    }

    @Test("A favorite pin shows a mood after enable; running-only tiles do not")
    func favoritePinsOnly() throws {
        let suite = "SimsFavorite.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let enabledAt = Date(timeIntervalSince1970: 1_700_000_000)
        sims.start()
        sims.setEnabled(true, at: enabledAt)
        let pin = try #require(sims.pinState(for: "safari", isFavorite: true, at: enabledAt))
        #expect(pin.mood(at: enabledAt) == .playful)
        #expect(pin.idle(at: enabledAt) == .bounce)
        #expect(sims.pinState(for: "safari", isFavorite: false, at: enabledAt) == nil)
    }

    @Test("Hunger and loneliness derive from elapsed care, not stored mood names")
    func moodClock() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(DockSimsMood.derive(hunger: 0, happiness: 1) == .playful)
        #expect(DockSimsMood.derive(hunger: 0.4, happiness: 0.8) == .content)
        #expect(DockSimsMood.derive(hunger: 0.8, happiness: 0.1) == .hungry)
        #expect(DockSimsMood.derive(hunger: 0.2, happiness: 0.2) == .lonely)

        #expect(DockSimsLimits.hunger(since: start, at: start) == 0)
        #expect(DockSimsLimits.hunger(since: start, at: start.addingTimeInterval(DockSimsLimits.hungerPeriod)) == 1)
        #expect(DockSimsLimits.happiness(since: start, at: start) == 1)
        #expect(DockSimsLimits.happiness(since: start, at: start.addingTimeInterval(DockSimsLimits.lonelyPeriod)) == 0)
    }

    @Test("Feed, cheer, and settle move the clocks; reset moods undoes every pin")
    func careLoopReversible() throws {
        let suite = "SimsCare.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        sims.start()
        sims.setEnabled(true, at: start)
        let later = start.addingTimeInterval(DockSimsLimits.hungerPeriod)
        #expect(sims.pinState(for: "mail", isFavorite: true, at: later)?.mood(at: later) == .hungry)

        sims.care(.feed, pinID: "mail", at: later)
        #expect(sims.pinState(for: "mail", isFavorite: true, at: later)?.mood(at: later) == .lonely)

        sims.care(.cheer, pinID: "mail", at: later)
        #expect(sims.pinState(for: "mail", isFavorite: true, at: later)?.mood(at: later) == .playful)

        let afterCheer = later.addingTimeInterval(DockSimsLimits.lonelyPeriod)
        sims.care(.settle, pinID: "mail", at: afterCheer)
        #expect(sims.pinState(for: "mail", isFavorite: true, at: afterCheer)?.mood(at: afterCheer) == .playful)

        sims.resetMoods(at: afterCheer)
        #expect(sims.hasPets == false)
        #expect(sims.pinState(for: "mail", isFavorite: true, at: afterCheer)?.mood(at: afterCheer) == .playful)
        #expect(sims.isEnabled)
    }

    @Test("Turning Sims off hides overlays and keeps pets for the next enable")
    func disableKeepsPets() throws {
        let suite = "SimsDisable.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        sims.start()
        sims.setEnabled(true, at: start)
        sims.care(.feed, pinID: "calendar", at: start)
        sims.setEnabled(false, at: start)
        #expect(sims.pinState(for: "calendar", isFavorite: true, at: start) == nil)
        #expect(sims.hasPets)
        sims.setEnabled(true, at: start)
        #expect(sims.pinState(for: "calendar", isFavorite: true, at: start)?.lastFedAt == start)
    }

    @Test("Intensity snaps to the settings slider and scales the overlay")
    func intensitySlider() throws {
        let suite = "SimsIntensity.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        sims.start()
        sims.setEnabled(true)
        #expect(sims.intensity == DockSimsLimits.defaultIntensity)
        sims.setIntensity(72)
        #expect(sims.intensity == 70)
        sims.setIntensity(5)
        #expect(sims.intensity == 15)
        let state = try #require(sims.pinState(for: "notes", isFavorite: true))
        #expect(state.intensity == 0.15)
    }

    @Test("Corrupt bytes freeze edits and are not overwritten until an explicit reset")
    func corruptStorage() throws {
        let suite = "SimsCorrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: DockSimsLimits.storageKey)
        let sims = DockSimsStore(repository: DockSimsRepository(defaults: defaults))
        sims.start()
        #expect(sims.requiresReset)
        #expect(sims.storageFailed)
        sims.setEnabled(true)
        sims.care(.feed, pinID: "safari")
        #expect(defaults.data(forKey: DockSimsLimits.storageKey) == Data("not-json".utf8))
        sims.reset()
        #expect(sims.requiresReset == false)
        #expect(defaults.object(forKey: DockSimsLimits.storageKey) == nil)
        #expect(sims.isEnabled == false)
    }

    @Test("Invalid documents are refused and missing keys decode as opt-in off")
    func repositoryGuards() throws {
        let suite = "SimsRepo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = DockSimsRepository(defaults: defaults)
        #expect(try repository.load() == nil)

        var invalid = DockSimsDocument.empty
        invalid.intensity = 250
        #expect(throws: CocoaError.self) { try repository.save(invalid) }
        #expect(defaults.object(forKey: DockSimsLimits.storageKey) == nil)

        var valid = DockSimsDocument.empty
        valid.isEnabled = true
        valid.baselineAt = Date(timeIntervalSince1970: 1_700_000_000)
        try repository.save(valid)
        let loaded = try #require(try repository.load())
        #expect(loaded.isEnabled)
        #expect(loaded.intensity == DockSimsLimits.defaultIntensity)
    }

    @Test("The oldest pets are dropped when the document hits the pin cap")
    func petCap() throws {
        let suite = "SimsCap.\(UUID().uuidString)"
        let (sims, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        sims.start()
        sims.setEnabled(true, at: start)
        for index in 0..<(DockSimsLimits.maximumPets + 3) {
            sims.care(.feed, pinID: "app.\(index)", at: start.addingTimeInterval(TimeInterval(index)))
        }
        #expect(sims.document.pets.count == DockSimsLimits.maximumPets)
        #expect(sims.document.pets["app.0"] == nil)
        #expect(sims.document.pets["app.\(DockSimsLimits.maximumPets + 2)"] != nil)
    }
}
