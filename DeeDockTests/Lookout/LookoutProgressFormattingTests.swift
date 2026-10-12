import Foundation
import Testing
@testable import DeeDock

/// The progress card's words: the percentage never says 100 % early, the time left reads as an estimate, and the
/// engine's status maps to the right phase.
struct LookoutProgressFormattingTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    /// Foundation sets narrow and no-break spaces before "AM" and "%"; the words are what's under test.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: Percent

    @Test func percentRoundsDownAndSavesHundredForDone() {
        typealias F = LookoutProgressFormatting
        #expect(F.displayFraction(0.996) == 0.99)
        #expect(F.displayFraction(0.619) == 0.61)
        #expect(F.displayFraction(1) == 1)
        #expect(F.displayFraction(1.4) == 1)
        #expect(F.displayFraction(-0.2) == 0)
        #expect(F.percent(0.62, locale: english) == "62%")
        #expect(plain(F.percent(0.62, locale: german)) == "62 %")
    }

    @Test func fractionIsNilWithoutTotalAndFullWhenUpToDate() {
        #expect(LookoutProgressDisplay(phase: .counting, done: 0, total: nil).fraction == nil)
        #expect(LookoutProgressDisplay(phase: .reading, done: 1, total: 4).fraction == 0.25)
        #expect(LookoutProgressDisplay(phase: .upToDate, done: 0, total: nil).fraction == 1)
    }

    // MARK: Time left

    @Test func timeLeftPhrasing() {
        typealias F = LookoutProgressFormatting
        #expect(F.timeLeft(30, locale: english) == "Less than a minute left")
        #expect(F.timeLeft(369, locale: english) == "About 6 min left")
        #expect(F.timeLeft(89, locale: english) == "About 1 min left")
        // 88 minutes round to the nearest five past an hour.
        #expect(F.timeLeft(5_268, locale: english) == "About 1 hr, 30 min left")
        // Past ten hours only the hours remain.
        #expect(F.timeLeft(40_000, locale: english) == "About 11 hr left")
        #expect(F.timeLeft(369, locale: english, wide: true) == "About 6 minutes left")
        #expect(F.timeLeft(.infinity, locale: english) == "Less than a minute left")
    }

    @Test func timeLeftInGerman() {
        #expect(LookoutProgressFormatting.timeLeft(369, locale: german) == "Noch etwa 6 Min.")
        #expect(LookoutProgressFormatting.timeLeft(30, locale: german) == "Weniger als eine Minute")
    }

    // MARK: Counts

    @Test func countLines() {
        typealias F = LookoutProgressFormatting
        #expect(F.countLine(done: 3_210, total: 5_202, locale: english) == "3,210 of 5,202 files")
        #expect(F.countLine(done: 3_210, total: 5_202, locale: german) == "3.210 von 5.202 Dateien")
        #expect(F.countLine(done: 96, total: nil, locale: english) == "96 files")
        #expect(F.countingLine(total: 1_860, locale: english) == "1,860 files so far · still counting")
        #expect(F.countingLine(total: 1, locale: english) == "1 file so far · still counting")
        #expect(F.countingLine(total: nil, locale: english) == "Nothing counted yet")
        #expect(F.rate(5.42, locale: english) == "5.4 files per second")
        #expect(F.rate(12.6, locale: german) == "13 Dateien pro Sekunde")
    }

    // MARK: Finished

    @Test func finishedTodayYesterdayOrOnADate() throws {
        typealias F = LookoutProgressFormatting
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 15)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10, minute: 41)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let earlier = try #require(calendar.date(byAdding: .day, value: -9, to: today))
        #expect(plain(F.finished(today, now: now, calendar: calendar, locale: english)) == "finished at 10:41 AM")
        #expect(plain(F.finished(yesterday, now: now, calendar: calendar, locale: english))
                == "finished yesterday at 10:41 AM")
        #expect(plain(F.finished(earlier, now: now, calendar: calendar, locale: english))
                == "finished Oct 3, 2026 at 10:41 AM")
        #expect(F.finished(today, now: now, calendar: calendar, locale: german) == "fertig um 10:41")
    }

    // MARK: Copy

    @Test func summaryCopyAnswersTheQuestions() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let reading = LookoutProgressCopy(progress: .Sample.readingMid, locale: english, now: now)
        #expect(reading.title == "Reading files")
        #expect(reading.subtitle == "3,210 of 5,202 files · About 6 min left")
        #expect(reading.detail == "5.4 files per second")
        #expect(reading.accessibilityLabel == "Lookout is reading files")
        #expect(reading.accessibilityValue == "61%, 3,210 of 5,202 files, About 6 minutes left")

        let early = LookoutProgressCopy(progress: .Sample.readingEarly, locale: english, now: now)
        #expect(early.subtitle == "96 of 5,202 files · Estimating time left")
        #expect(early.detail == nil)

        let counting = LookoutProgressCopy(progress: .Sample.counting, locale: english, now: now)
        #expect(counting.title == "Looking through your folders…")
        #expect(counting.subtitle == "1,860 files so far · still counting")

        let paused = LookoutProgressCopy(progress: .Sample.pausedLowPower, locale: english, now: now)
        #expect(paused.title == "Paused")
        #expect(paused.subtitle == "Low Power Mode · 1,992 files left")

        let drive = LookoutProgressCopy(progress: .Sample.waitingForDrive, locale: english, now: now)
        #expect(drive.title == "Waiting for “Backup Drive”")
        #expect(drive.detail == "222 files left")

        let done = LookoutProgressCopy(progress: .Sample.upToDate(now: now), locale: english, now: now)
        #expect(done.title == "Up to date")
        #expect(done.subtitle.hasPrefix("5,202 files · finished at "))
    }

    // MARK: Engine mapping

    @Test func engineStatusMapsToPhases() {
        var index = LookoutIndexStatus()
        index.activity = .indexing
        index.counts.byKindAndState = ["image": ["done": 40, "pending": 60, "skipped": 2],
                                       "pdf": ["pending": 10, "failed": 1]]

        let reading = LookoutProgressDisplay(status: .indexing(remaining: 70, progress: 0.4), index: index)
        #expect(reading?.phase == .reading)
        #expect(reading?.done == 43 && reading?.total == 113 && reading?.remaining == 70)
        #expect(reading?.totalIsFinal == true)
        #expect(reading?.kinds[.image] == .init(done: 42, total: 102))
        #expect(reading?.kinds[.pdf] == .init(done: 1, total: 11))
        #expect(reading?.skipped == 2 && reading?.failed == 1)
        #expect(reading?.estimatedRemaining == nil && reading?.filesPerSecond == nil)

        #expect(LookoutProgressDisplay(status: .indexing(remaining: nil, progress: nil), index: nil)?.phase == .counting)
        var syncing = LookoutIndexStatus()
        syncing.activity = .syncing
        #expect(LookoutProgressDisplay(status: .indexing(remaining: 0, progress: nil), index: syncing)?.phase == .counting)
        index.activity = .syncing
        let laterSync = LookoutProgressDisplay(status: .indexing(remaining: 70, progress: nil), index: index)
        #expect(laterSync?.phase == .reading && laterSync?.totalIsFinal == false)

        #expect(LookoutProgressDisplay(status: .ready, index: index)?.phase == .upToDate)
        #expect(LookoutProgressDisplay(status: .paused(.warm), index: index)?.phase == .paused(reason: .thermal))
        #expect(LookoutProgressDisplay(status: .failed(LookoutFailure(kind: .service)), index: index)?.phase
                == .failed(message: LookoutFailure(kind: .service).message))
        #expect(LookoutProgressDisplay(status: .notSetUp, index: index) == nil)
        #expect(LookoutProgressDisplay(status: .off, index: index) == nil)
        #expect(LookoutProgressDisplay(status: .waitingForModel, index: index) == nil)
    }
}
