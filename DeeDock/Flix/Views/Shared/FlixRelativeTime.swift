import Foundation

/// The row's trailing time: "now", "12 min", a clock time for today and yesterday, a date before.
enum FlixRelativeTime {
    static func string(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: .flixTimeNow) }
        if seconds < 3_600 { return String(localized: .flixTimeMinutes(Int(seconds / 60))) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        if calendar.isDate(date, inSameDayAs: now) || calendar.isDate(date, inSameDayAs: yesterday) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
