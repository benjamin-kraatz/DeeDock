import Foundation

/// When a query says its file is from, in German or English: "März 2024", "letzten Sommer", "15.10.2026",
/// "vor drei Wochen", "early 2024", "last month". `Searcher` boosts files dated inside the range
/// (`LookoutRanking.dateBonus`); it never drops the others, so a misread date costs rank, not the file.
///
/// The parser reads whole words and the numbers beside them, and takes the most specific expression it finds (a day
/// over a month over a season over a year). A month or season without a year means its latest occurrence that has
/// begun by `now`. A year is a standalone number from 1990 to 2099; digits inside a code ("MW-2024-0047") are not a
/// date.
nonisolated struct DateHint: Equatable, Sendable {
    /// The range a matching file's date falls in: start inclusive, end exclusive.
    let interval: DateInterval

    /// The date `text` names, relative to `now`, or nil when it names none.
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .lookout) -> DateHint? {
        let words = text.lowercased()
            .replacingOccurrences(of: #"(\d)\.(\d)"#, with: "$1§$2", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: " ,;:!?()\"'„“”").union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).replacingOccurrences(of: "§", with: ".") }
            .filter { !$0.isEmpty }
        return Parser(words: words, now: now, calendar: calendar).best().map(DateHint.init(interval:))
    }

    /// The date a file counts as from: when its picture was taken, else when it last changed.
    static func fileDate(modified: Double, info: [String: String]) -> Date {
        if let taken = info["taken"], let date = exif.date(from: taken) { return date }
        return Date(timeIntervalSince1970: modified)
    }

    private static let exif: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}

extension Calendar {
    /// Gregorian in the current time zone, weeks starting on Monday: how the dates in a query are meant.
    nonisolated static var lookout: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
}

nonisolated private struct Parser {
    let words: [String]
    let now: Date
    let calendar: Calendar

    /// What was found, most specific first.
    private enum Precision: Int, Comparable {
        case year, part, season, month, week, day
        static func < (a: Precision, b: Precision) -> Bool { a.rawValue < b.rawValue }
    }

    private static let months: [String: Int] = [
        "januar": 1, "jänner": 1, "january": 1, "jan": 1, "februar": 2, "february": 2, "feb": 2, "märz": 3,
        "maerz": 3, "march": 3, "mär": 3, "mar": 3, "april": 4, "apr": 4, "mai": 5, "may": 5, "juni": 6, "june": 6,
        "jun": 6, "juli": 7, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
        "oktober": 10, "october": 10, "okt": 10, "oct": 10, "november": 11, "nov": 11, "dezember": 12,
        "december": 12, "dez": 12, "dec": 12,
    ]
    /// Each season's first month and length; winter starts in December of the year before its January.
    private static let seasons: [String: Int] = [
        "frühling": 3, "frühjahr": 3, "spring": 3, "sommer": 6, "summer": 6, "herbst": 9, "autumn": 9, "fall": 9,
        "winter": 12,
    ]
    private static let units: [String: Calendar.Component] = [
        "tag": .day, "tagen": .day, "tage": .day, "day": .day, "days": .day, "woche": .weekOfYear,
        "wochen": .weekOfYear, "week": .weekOfYear, "weeks": .weekOfYear, "monat": .month, "monaten": .month,
        "monate": .month, "month": .month, "months": .month, "jahr": .year, "jahren": .year, "jahre": .year,
        "year": .year, "years": .year,
    ]
    private static let numbers: [String: Int] = [
        "ein": 1, "einem": 1, "einer": 1, "a": 1, "an": 1, "one": 1, "zwei": 2, "two": 2, "drei": 3, "three": 3,
        "vier": 4, "four": 4, "fünf": 5, "five": 5, "sechs": 6, "six": 6,
    ]
    private static let last: Set<String> = ["letzten", "letzte", "letztes", "letzter", "vergangenen", "vergangene",
                                            "vergangenes", "vorigen", "voriges", "vorige", "last", "past", "previous"]
    private static let this: Set<String> = ["diesen", "diese", "dieses", "diesem", "dieser", "this", "current"]
    private static let early: Set<String> = ["anfang", "early", "beginning"]
    private static let mid: Set<String> = ["mitte", "mid", "middle"]
    private static let late: Set<String> = ["ende", "late", "end"]

    init(words: [String], now: Date, calendar: Calendar) {
        self.words = words
        self.now = now
        self.calendar = calendar
    }

    func best() -> DateInterval? {
        var found: [(Precision, DateInterval)] = []
        for index in words.indices {
            if let hit = numericDate(at: index) { found.append(hit) }
            if let hit = monthName(at: index) { found.append(hit) }
            if let hit = season(at: index) { found.append(hit) }
            if let hit = relative(at: index) { found.append(hit) }
            if let hit = ago(at: index) { found.append(hit) }
            if let hit = year(at: index) { found.append(hit) }
        }
        return found.max { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Pieces

    private func word(_ index: Int) -> String? { words.indices.contains(index) ? words[index] : nil }

    private func yearValue(_ text: String?) -> Int? {
        guard let text, text.count == 4, let value = Int(text), (1990...2099).contains(value) else { return nil }
        return value
    }

    private func dayValue(_ text: String?) -> Int? {
        guard let text, let value = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "."))),
              (1...31).contains(value), text.count <= 3 else { return nil }
        return value
    }

    private func start(_ year: Int, _ month: Int, _ day: Int = 1) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func interval(from start: Date?, adding component: Calendar.Component, _ value: Int) -> DateInterval? {
        guard let start, let end = calendar.date(byAdding: component, value: value, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The latest year in which `month` has begun by `now`.
    private func latestYear(of month: Int) -> Int {
        let current = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) >= month ? current : current - 1
    }

    /// "15.10.2026", "15.10.26", "2026-10-15".
    private func numericDate(at index: Int) -> (Precision, DateInterval)? {
        let text = words[index]
        let parts: [Int]
        if text.contains("."), text.split(separator: ".").count == 3 {
            parts = text.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            let year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
            return valid(year, parts[1], parts[0])
        }
        if text.count == 10, text.split(separator: "-").count == 3 {
            parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return valid(parts[0], parts[1], parts[2])
        }
        return nil
    }

    private func valid(_ year: Int, _ month: Int, _ day: Int) -> (Precision, DateInterval)? {
        guard (1990...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        return interval(from: start(year, month, day), adding: .day, 1).map { (.day, $0) }
    }

    /// "15. Oktober 2026", "October 15, 2026", "Oktober 2026", "im März", "Anfang Mai 2024".
    private func monthName(at index: Int) -> (Precision, DateInterval)? {
        guard let month = Self.months[words[index]] else { return nil }
        // Bare short forms ("mar", "may", "jun") are words too often; they count only beside a number.
        let short = words[index].count <= 4 && !["juni", "juli", "mai"].contains(words[index])
        let dayBefore = dayValue(word(index - 1)), dayAfter = dayValue(word(index + 1))
        let yearAfter = yearValue(word(index + 1)) ?? yearValue(word(index + 2))
        guard !short || dayBefore != nil || dayAfter != nil || yearAfter != nil else { return nil }
        let year = yearAfter ?? latestYear(of: month)
        if let day = dayBefore ?? (yearValue(word(index + 1)) == nil ? dayAfter : nil) {
            return valid(year, month, day)
        }
        return interval(from: start(year, month), adding: .month, 1).map { (.month, $0) }
    }

    /// "Sommer 2024", "letzten Winter", "last summer".
    private func season(at index: Int) -> (Precision, DateInterval)? {
        guard let month = Self.seasons[words[index]] else { return nil }
        var year: Int
        if let given = yearValue(word(index + 1)) {
            year = given
        } else {
            // The latest one that has begun; "letzten" (last) means the one before that if it's still going.
            year = latestYear(of: month)
            if let first = start(year, month), calendar.date(byAdding: .month, value: 3, to: first)! > now,
               Self.last.contains(word(index - 1) ?? "") {
                year -= 1
            }
        }
        if month == 12, yearValue(word(index + 1)) != nil {
            // "Winter 2024" is the one that starts in December 2023 and holds January and February 2024.
            year -= 1
        }
        return interval(from: start(year, month), adding: .month, 3).map { (.season, $0) }
    }

    /// "letzten Monat", "this year", "letzte Woche", "heute", "gestern", "Anfang 2024".
    private func relative(at index: Int) -> (Precision, DateInterval)? {
        let text = words[index]
        let today = calendar.startOfDay(for: now)
        if text == "heute" || text == "today" { return interval(from: today, adding: .day, 1).map { (.day, $0) } }
        if text == "gestern" || text == "yesterday" {
            return interval(from: calendar.date(byAdding: .day, value: -1, to: today), adding: .day, 1).map { (.day, $0) }
        }
        if text == "vorgestern" {
            return interval(from: calendar.date(byAdding: .day, value: -2, to: today), adding: .day, 1).map { (.day, $0) }
        }
        if let year = yearValue(text), let part = word(index - 1),
           Self.early.contains(part) || Self.mid.contains(part) || Self.late.contains(part) {
            let offset = Self.early.contains(part) ? 0 : Self.mid.contains(part) ? 4 : 8
            return interval(from: start(year, 1 + offset), adding: .month, 4).map { (.part, $0) }
        }
        guard let unit = Self.units[text], let before = word(index - 1),
              Self.last.contains(before) || Self.this.contains(before) else { return nil }
        let component: Calendar.Component = unit == .weekOfYear ? .weekOfYear : unit
        guard let current = calendar.dateInterval(of: component, for: now) else { return nil }
        let offset = Self.last.contains(before) ? -1 : 0
        let precision: Precision = switch unit {
        case .day: .day
        case .weekOfYear: .week
        case .month: .month
        default: .year
        }
        return interval(from: calendar.date(byAdding: component, value: offset, to: current.start), adding: component, 1)
            .map { (precision, $0) }
    }

    /// "vor drei Wochen", "2 months ago": the unit around that point.
    private func ago(at index: Int) -> (Precision, DateInterval)? {
        guard let unit = Self.units[words[index]] else { return nil }
        let german = word(index - 2) == "vor"
        let english = word(index + 1) == "ago"
        guard german || english, let countWord = word(index - 1),
              let count = Int(countWord) ?? Self.numbers[countWord] else { return nil }
        guard let point = calendar.date(byAdding: unit, value: -count, to: now),
              let around = calendar.dateInterval(of: unit == .day ? .day : unit, for: point) else { return nil }
        // A little slack either side: "vor drei Wochen" is rarely exactly that week.
        let slack = around.duration / 2
        return (unit == .day ? .day : unit == .weekOfYear ? .week : unit == .month ? .month : .year,
                DateInterval(start: around.start.addingTimeInterval(-slack), end: around.end.addingTimeInterval(slack)))
    }

    /// "2024", "aus 2024", "in 2024".
    private func year(at index: Int) -> (Precision, DateInterval)? {
        guard let year = yearValue(words[index]) else { return nil }
        return interval(from: start(year, 1), adding: .year, 1).map { (.year, $0) }
    }
}
