import Foundation
import Testing

@MainActor
struct PinWeatherTests {
    private func store(_ suite: String) throws -> (PinWeatherStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (PinWeatherStore(repository: PinWeatherRepository(defaults: defaults)), defaults)
    }

    @Test("Rust stays off until the unused-day threshold, then weathers instead of flipping to alarm")
    func intensityRamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let days = 30
        #expect(PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: true, now: now) == 0)
        let almost = now.addingTimeInterval(Double(days) * PinWeatherLimits.secondsPerDay - 1)
        #expect(PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: true, now: almost) == 0)
        let atThreshold = now.addingTimeInterval(Double(days) * PinWeatherLimits.secondsPerDay)
        let starting = PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: true, now: atThreshold)
        #expect(starting == 0.32)
        let halfway = now.addingTimeInterval(Double(days) * 1.5 * PinWeatherLimits.secondsPerDay)
        let mid = PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: true, now: halfway)
        #expect(abs(mid - 0.66) < 0.01)
        let fully = now.addingTimeInterval(Double(days) * 2 * PinWeatherLimits.secondsPerDay)
        #expect(PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: true, now: fully) == 1)
        #expect(PinWeatherIntensity.value(lastUsed: now, unusedDays: days, enabled: false, now: fully) == 0)
        #expect(PinWeatherIntensity.value(lastUsed: nil, unusedDays: days, enabled: true, now: now) == 0)
        #expect(PinWeatherIntensity.value(lastUsed: now, unusedDays: 0, enabled: true, now: fully) == 0)
    }

    @Test("Using a pin clears rust; timestamps stay local to the supplied defaults")
    func useReversesRust() throws {
        let suite = "PinWeatherUse.\(UUID().uuidString)"
        let (weather, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        weather.start()
        let start = Date(timeIntervalSince1970: 1_000)
        weather.synchronize(pinIDs: ["safari"], at: start)
        let unused = start.addingTimeInterval(Double(weather.unusedDays) * 2 * PinWeatherLimits.secondsPerDay)
        #expect(weather.intensity(for: "safari", at: unused) == 1)
        weather.recordUse("safari", at: unused)
        #expect(weather.intensity(for: "safari", at: unused) == 0)
        #expect(weather.lastUsed(for: "safari") == unused)

        let reloaded = PinWeatherStore(repository: PinWeatherRepository(defaults: defaults))
        reloaded.start()
        #expect(reloaded.lastUsed(for: "safari") == unused)
        #expect(reloaded.intensity(for: "safari", at: unused) == 0)
    }

    @Test("Synchronize stamps unseen pins as now and drops identities that are no longer pinned")
    func synchronizeStampsAndPrunes() throws {
        let suite = "PinWeatherSync.\(UUID().uuidString)"
        let (weather, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        weather.start()
        let first = Date(timeIntervalSince1970: 2_000)
        weather.synchronize(pinIDs: ["safari", "mail"], at: first)
        #expect(weather.lastUsed(for: "safari") == first)
        #expect(weather.lastUsed(for: "mail") == first)
        let later = first.addingTimeInterval(10)
        weather.recordUse("safari", at: later)
        weather.synchronize(pinIDs: ["safari", "notes"], at: later)
        #expect(weather.lastUsed(for: "safari") == later)
        #expect(weather.lastUsed(for: "mail") == nil)
        #expect(weather.lastUsed(for: "notes") == later)
    }

    @Test("Settings survive a timestamp clear; corrupt bytes do not get overwritten")
    func clearAndCorrupt() throws {
        let suite = "PinWeatherClear.\(UUID().uuidString)"
        let (weather, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        weather.start()
        weather.setEnabled(false)
        weather.setUnusedDays(14)
        weather.recordUse("safari", at: Date(timeIntervalSince1970: 3_000))
        weather.clearTimestamps()
        #expect(weather.lastUsed(for: "safari") == nil)
        #expect(weather.enabled == false)
        #expect(weather.unusedDays == 14)

        defaults.set(Data("not-json".utf8), forKey: "dock.pin-weather.v1")
        let frozen = PinWeatherStore(repository: PinWeatherRepository(defaults: defaults))
        frozen.start()
        #expect(frozen.requiresReset)
        #expect(frozen.storageFailed)
        frozen.setUnusedDays(7)
        frozen.recordUse("mail")
        #expect(frozen.unusedDays == PinWeatherLimits.defaultUnusedDays)
        #expect(frozen.lastUsed(for: "mail") == nil)
        let leftover = try #require(defaults.data(forKey: "dock.pin-weather.v1"))
        #expect(String(data: leftover, encoding: .utf8) == "not-json")
        frozen.reset()
        #expect(!frozen.requiresReset)
        #expect(frozen.enabled)
        #expect(defaults.object(forKey: "dock.pin-weather.v1") == nil)
    }

    @Test("Older documents without keys load factory weather defaults")
    func missingKeysDefault() throws {
        let suite = "PinWeatherLegacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([String: String]()), forKey: "dock.pin-weather.v1")
        let weather = PinWeatherStore(repository: PinWeatherRepository(defaults: defaults))
        weather.start()
        #expect(weather.enabled)
        #expect(weather.unusedDays == 30)
        #expect(weather.isEmpty)
    }
}
