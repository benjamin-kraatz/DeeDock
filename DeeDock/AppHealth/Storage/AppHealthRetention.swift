import Foundation

/// How long App Health keeps files and how much space they may take. Pure, so the rules are testable.
///
/// Applied when the store opens, after each daily rotation, and whenever the tracked total passes the cap:
/// first every file more than `maximumAgeDays` old goes, then the oldest files go one by one while the total is
/// still above `maximumBytes`. Today's file is never deleted; if it alone passes the cap, the store stops appending
/// until tomorrow instead (see `isOverCap`).
nonisolated struct AppHealthRetention: Sendable, Equatable {
    /// Days of history kept. A file dated more than this many days before today is deleted.
    var maximumAgeDays = 30
    /// Total bytes kept across all files. Decimal megabytes, matching how Settings shows sizes.
    var maximumBytes: Int64 = 50_000_000

    static let standard = AppHealthRetention()

    struct File: Sendable, Equatable {
        let day: AppHealthDay
        let bytes: Int64
    }

    /// The days whose files to delete, oldest first.
    func filesToDelete(_ files: [File], today: AppHealthDay, calendar: Calendar) -> [AppHealthDay] {
        var kept: [File] = []
        var deleted: [AppHealthDay] = []
        for file in files.sorted(by: { $0.day < $1.day }) {
            if file.day != today, let age = file.day.days(until: today, calendar: calendar), age > maximumAgeDays {
                deleted.append(file.day)
            } else {
                kept.append(file)
            }
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.bytes }
        for file in kept where total > maximumBytes && file.day != today {
            deleted.append(file.day)
            total -= file.bytes
        }
        return deleted
    }

    /// Whether today's file alone has reached the cap, so appending must wait for tomorrow's file.
    func isOverCap(todayBytes: Int64) -> Bool {
        todayBytes >= maximumBytes
    }
}
