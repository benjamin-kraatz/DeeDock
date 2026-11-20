import Foundation

/// The list's time sections: Just Now, Today, Yesterday, Earlier.
nonisolated enum FlixTimeGroup: Int, CaseIterable, Comparable, Sendable {
    case justNow, today, yesterday, earlier

    /// How recent "Just Now" is.
    static let justNowInterval: TimeInterval = 10 * 60

    /// The section `date` belongs to, seen from `now` in `calendar`. A date in the future (a clock
    /// change, a file stamped ahead) counts as Just Now rather than disappearing.
    static func group(for date: Date, now: Date, calendar: Calendar = .current) -> FlixTimeGroup {
        if now.timeIntervalSince(date) < justNowInterval { return .justNow }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }

    var title: LocalizedStringResource {
        switch self {
        case .justNow: .flixGroupJustNow
        case .today: .flixGroupToday
        case .yesterday: .flixGroupYesterday
        case .earlier: .flixGroupEarlier
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
