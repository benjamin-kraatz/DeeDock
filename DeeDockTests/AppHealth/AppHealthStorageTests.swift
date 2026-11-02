import Foundation
import Testing
@testable import DeeDock

/// The record store in a temporary directory, and the persisted labelling preferences.
struct AppHealthStorageTests {
    /// A clock the test moves forward; the store reads it on its own actor.
    nonisolated private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { lock.withLock { value } }
        func advance(days: Int) { lock.withLock { value = value.addingTimeInterval(Double(days) * 86_400) } }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func record(_ clock: Clock) -> AppHealthRecord {
        AppHealthRecord(.event(.collector(.collectorStart, reason: .enabled)), at: clock.now)
    }

    @Test("Appends one line per record, rotates daily, prunes past 30 days, and deletes everything")
    func appendRotateDelete() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AppHealthStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(Date(timeIntervalSince1970: 1_793_000_000))
        let store = AppHealthRecordStore(directory: directory, calendar: Self.calendar, now: { clock.now })

        await store.append([record(clock), record(clock)])
        clock.advance(days: 1)
        await store.append([record(clock)])
        var summary = await store.summary()
        #expect(summary.days == 2)
        #expect(summary.hasData)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files.count == 2)
        let first = try String(contentsOf: directory.appending(path: files[0]), encoding: .utf8)
        #expect(first.split(separator: "\n").count == 2)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appending(path: files[0]).path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        clock.advance(days: 31)
        await store.append([record(clock)])
        summary = await store.summary()
        // The first day is now 32 days old; the second 31: both expired.
        #expect(summary.days == 1)

        try await store.deleteAll()
        #expect(await store.summary() == .empty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    @Test("Pausing lasts until the next local midnight; preferences persist and keep fields they do not own")
    func labellingPreferences() throws {
        let suite = "AppHealthStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONSerialization.data(withJSONObject: ["recentPrompts": [1, 2]]),
                     forKey: AppHealthLabellingPreferences.defaultsKey)
        let noon = Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let preferences = AppHealthLabellingPreferences(defaults: defaults, calendar: Self.calendar, now: { noon })

        preferences.pauseForToday()
        #expect(preferences.pausedUntil == Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        #expect(preferences.isPaused)
        #expect(!preferences.isPaused(at: noon.addingTimeInterval(12 * 3600)))
        #expect(preferences.addDontAsk("com.example.App"))
        #expect(!preferences.addDontAsk("com.example.App"))

        let reloaded = AppHealthLabellingPreferences(defaults: defaults, calendar: Self.calendar, now: { noon })
        #expect(reloaded.dontAsk == ["com.example.App"])
        #expect(reloaded.isPaused)
        #expect(reloaded.resume())
        #expect(!reloaded.resume())
        let stored = try #require(defaults.data(forKey: AppHealthLabellingPreferences.defaultsKey))
        let object = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(object["recentPrompts"] != nil)
        #expect(object["pausedUntil"] == nil)
    }
}
