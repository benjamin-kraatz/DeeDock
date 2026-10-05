import Foundation
import Testing
@testable import DeeDock

@Suite("Focus countdown labels")
struct FocusSessionTimeLabelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let english = Locale(identifier: "en_US")
    private var englishCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = english
        return calendar
    }

    @Test("Under an hour stays MM:SS and an hour or more shows H:MM:SS", arguments: [
        (TimeInterval(59 * 60 + 59), "59:59"),
        (TimeInterval(60 * 60), "1:00:00"),
        (TimeInterval(90 * 60 + 5), "1:30:05"),
        (TimeInterval(3 * 60 * 60), "3:00:00"),
        (TimeInterval(0), "00:00"),
    ])
    func timeLabel(remaining: TimeInterval, expected: String) {
        let session = running(remaining: remaining)
        #expect(session.timeLabel(at: now) == expected)
        #expect(session.showsHours(at: now) == (remaining >= 3_600))
    }

    @Test("A fraction of a second at the hour boundary rounds up to 1:00:00")
    func fractionalHourBoundary() {
        let session = running(remaining: 3_599.1)
        #expect(session.timeLabel(at: now) == "1:00:00")
        #expect(session.showsHours(at: now))
        let spoken = speak(session, at: now)
        #expect(spoken.contains("hour"))
        #expect(!spoken.contains("minute"))
        #expect(!spoken.contains("second"))
    }

    @Test("A paused session keeps the stored remainder when the clock moves")
    func pausedRemainder() {
        let session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing",
                                   duration: 5_405, remainingWhenPaused: 5_405, deadline: nil, phase: .paused)
        let later = now.addingTimeInterval(10_000)
        #expect(session.timeLabel(at: now) == "1:30:05")
        #expect(session.timeLabel(at: later) == "1:30:05")
        let spoken = speak(session, at: later)
        #expect(spoken.contains("hour"))
        #expect(spoken.contains("minute"))
        #expect(spoken.contains("second"))
    }

    @Test("Spoken remaining names each non-zero unit", arguments: [
        (TimeInterval(0), false, false, true),
        (TimeInterval(60 * 60), true, false, false),
        (TimeInterval(90 * 60 + 5), true, true, true),
        (TimeInterval(59 * 60 + 59), false, true, true),
    ])
    func spokenRemaining(remaining: TimeInterval, hour: Bool, minute: Bool, second: Bool) {
        let session = running(remaining: remaining)
        #expect(!session.spokenRemaining(at: now).isEmpty)
        let spoken = speak(session, at: now)
        #expect(spoken.contains("hour") == hour)
        #expect(spoken.contains("minute") == minute)
        #expect(spoken.contains("second") == second)
        #expect(!spoken.contains(":"))
    }

    private func running(remaining: TimeInterval) -> FocusSession {
        FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing",
                     duration: max(remaining, 60), remainingWhenPaused: 0,
                     deadline: now.addingTimeInterval(remaining), phase: .running)
    }

    /// English stems only, so a different "and" or digit style in the spell-out still passes.
    private func speak(_ session: FocusSession, at date: Date) -> String {
        session.spokenRemaining(at: date, locale: english, calendar: englishCalendar)
    }
}
