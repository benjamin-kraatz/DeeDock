import Foundation

/// The words and numbers of the progress card, as pure functions of a `LookoutProgressDisplay`, so the phrasing can
/// be tested without a view: the percentage, "3,210 of 5,202 files", "About 6 min left", "finished at 10:41".
///
/// Every function takes a `locale` (and the date ones a `now` and a `calendar`) so tests are deterministic.
nonisolated enum LookoutProgressFormatting {
    // MARK: Percent

    /// The fraction as the card shows it: whole percent, rounded down, and 100 % only once nothing is left. A pass
    /// 99.6 % through still reads "99 %", so "100 %" always means done.
    static func displayFraction(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        if clamped >= 1 { return 1 }
        return min(floor(clamped * 100), 99) / 100
    }

    /// "62 %" in the locale's form ("62%" in English, "62 %" in German).
    static func percent(_ fraction: Double, locale: Locale = .current) -> String {
        displayFraction(fraction).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    // MARK: Counts

    /// "3,210 of 5,202 files"; "3,210 files" when the total isn't known.
    static func countLine(done: Int, total: Int?, locale: Locale = .current) -> String {
        if let total {
            return localized(.lookoutProgressOfFiles(number(done, locale), number(total, locale)), locale)
        }
        return localized(.lookoutSetupFiles(done), locale)
    }

    /// While counting: "1,860 files so far · still counting", or "Nothing counted yet".
    static func countingLine(total: Int?, locale: Locale = .current) -> String {
        guard let total, total > 0 else { return localized(.lookoutProgressCountingNothingYet, locale) }
        return localized(.lookoutProgressCountingSoFar(total), locale)
    }

    /// "5.4 files per second", with one decimal under ten and none above.
    static func rate(_ filesPerSecond: Double, locale: Locale = .current) -> String {
        let digits = filesPerSecond < 10 ? 1 : 0
        let text = filesPerSecond.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return localized(.lookoutProgressRate(text), locale)
    }

    // MARK: Time

    /// "About 6 min left", "About 1 hr, 25 min left", or "Less than a minute left". Minutes are rounded; past an
    /// hour they're rounded to five, and past ten hours only hours remain, since the estimate is never that exact.
    /// `wide` spells the units out ("about 6 minutes left") for VoiceOver.
    static func timeLeft(_ seconds: TimeInterval, locale: Locale = .current, wide: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 60 else { return localized(.lookoutProgressLessThanMinute, locale) }
        var minutes = Int((seconds / 60).rounded())
        if minutes >= 600 {
            minutes = Int((Double(minutes) / 60).rounded()) * 60
        } else if minutes >= 60 {
            minutes = Int((Double(minutes) / 5).rounded()) * 5
        }
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        let text = Duration.seconds(minutes * 60)
            .formatted(.units(allowed: allowed, width: wide ? .wide : .abbreviated, maximumUnitCount: 2).locale(locale))
        return localized(.lookoutProgressTimeLeft(text), locale)
    }

    /// "finished at 10:41" today, "finished yesterday at 10:41", else "finished Oct 3, 10:41". Days and times are
    /// the calendar's, in its time zone: "today" and "10:41" always agree, whatever zone the process runs in.
    static func finished(_ date: Date, now: Date = .now, calendar: Calendar = .current,
                         locale: Locale = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) {
            return localized(.lookoutProgressFinishedToday(time), locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return localized(.lookoutProgressFinishedYesterday(time), locale)
        }
        let day = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale,
                                                  calendar: calendar, timeZone: calendar.timeZone))
        return localized(.lookoutProgressFinishedOn(day), locale)
    }

    // MARK: Helpers

    private static func number(_ value: Int, _ locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// The resource in `locale`, not the process's.
    static func localized(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
