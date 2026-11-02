import Foundation
import Testing
@testable import DeeDock

/// Retention keeps 30 days and 50 MB, deletes the oldest first, and never deletes today's file.
struct AppHealthRetentionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    private let today = AppHealthDay(year: 2026, month: 11, day: 2)
    private let megabyte: Int64 = 1_000_000

    private func day(_ offset: Int) -> AppHealthDay {
        let start = today.start(in: calendar)!
        return AppHealthDay(calendar.date(byAdding: .day, value: -offset, to: start)!, calendar: calendar)
    }

    @Test("Files more than 30 days old are deleted; a 30-day-old file stays")
    func maximumAge() {
        let files = [0, 1, 30, 31, 45].map { AppHealthRetention.File(day: day($0), bytes: megabyte) }
        let deleted = AppHealthRetention.standard.filesToDelete(files, today: today, calendar: calendar)
        #expect(deleted == [day(45), day(31)])
    }

    @Test("Over the size cap, the oldest files go first until the total fits")
    func sizeCapOldestFirst() {
        let files = [0, 1, 2, 3].map { AppHealthRetention.File(day: day($0), bytes: 20 * megabyte) }
        let deleted = AppHealthRetention.standard.filesToDelete(files.shuffled(), today: today, calendar: calendar)
        // 80 MB → delete day 3 (60 MB) → still over → delete day 2 (40 MB).
        #expect(deleted == [day(3), day(2)])
    }

    @Test("Today's file is never deleted, even when it alone is over the cap")
    func neverToday() {
        let files = [AppHealthRetention.File(day: today, bytes: 70 * megabyte),
                     AppHealthRetention.File(day: day(1), bytes: megabyte)]
        let deleted = AppHealthRetention.standard.filesToDelete(files, today: today, calendar: calendar)
        #expect(deleted == [day(1)])
        #expect(AppHealthRetention.standard.isOverCap(todayBytes: 70 * megabyte))
        #expect(!AppHealthRetention.standard.isOverCap(todayBytes: 49 * megabyte))
    }

    @Test("Age and size rules combine: expired files go, then the oldest of the rest")
    func combined() {
        let files = [AppHealthRetention.File(day: day(40), bytes: megabyte),
                     AppHealthRetention.File(day: day(10), bytes: 30 * megabyte),
                     AppHealthRetention.File(day: day(5), bytes: 15 * megabyte),
                     AppHealthRetention.File(day: today, bytes: 10 * megabyte)]
        let deleted = AppHealthRetention.standard.filesToDelete(files, today: today, calendar: calendar)
        #expect(deleted == [day(40), day(10)])
    }

    @Test("File names use the local date and round-trip; other names are ignored")
    func fileNames() {
        #expect(today.fileName == "app-health-2026-11-02.jsonl")
        #expect(AppHealthDay(fileName: "app-health-2026-11-02.jsonl") == today)
        #expect(AppHealthDay(fileName: "app-health-2026-13-02.jsonl") == nil)
        #expect(AppHealthDay(fileName: "manifest.json") == nil)
        #expect(AppHealthDay(fileName: "app-health-2026-11-02.jsonl.tmp") == nil)
        // 23:30 UTC on 1 Nov is already 2 Nov in Berlin.
        let lateUTC = ISO8601DateFormatter().date(from: "2026-11-01T23:30:00Z")!
        #expect(AppHealthDay(lateUTC, calendar: calendar) == today)
    }
}
