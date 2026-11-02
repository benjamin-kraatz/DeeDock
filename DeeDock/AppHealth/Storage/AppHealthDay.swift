import Foundation

/// A local calendar day, which names one App Health file: `app-health-2026-11-02.jsonl`.
///
/// Files are named by the local date so "today's file" matches what the person sees on the clock. A time-zone
/// change can therefore make two days' records share a file, or leave a day without one; `ts` in every record is
/// absolute, so nothing is lost.
nonisolated struct AppHealthDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    static let filePrefix = "app-health-"
    static let fileExtension = "jsonl"

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses a file name this store wrote; nil for anything else in the directory.
    init?(fileName: String) {
        guard fileName.hasPrefix(Self.filePrefix), fileName.hasSuffix("." + Self.fileExtension) else { return nil }
        let stem = fileName.dropFirst(Self.filePrefix.count).dropLast(Self.fileExtension.count + 1)
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var fileName: String {
        String(format: "%@%04d-%02d-%02d.%@", Self.filePrefix, year, month, day, Self.fileExtension)
    }

    /// The start of this day in `calendar`'s time zone.
    func start(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Whole calendar days from this day to `later`; negative when `later` is earlier.
    func days(until later: AppHealthDay, calendar: Calendar) -> Int? {
        guard let from = start(in: calendar), let to = later.start(in: calendar) else { return nil }
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    static func < (lhs: AppHealthDay, rhs: AppHealthDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
