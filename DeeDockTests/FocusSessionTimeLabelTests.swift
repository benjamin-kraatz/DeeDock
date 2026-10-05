import Foundation
import Testing
@testable import DeeDock

@Suite("Focus countdown labels")
struct FocusSessionTimeLabelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Under an hour stays MM:SS and an hour or more shows H:MM:SS", arguments: [
        (TimeInterval(59 * 60 + 59), "59:59"),
        (TimeInterval(60 * 60), "1:00:00"),
        (TimeInterval(90 * 60 + 5), "1:30:05"),
        (TimeInterval(3 * 60 * 60), "3:00:00"),
        (TimeInterval(0), "00:00"),
    ])
    func timeLabel(remaining: TimeInterval, expected: String) {
        let session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing",
                                   duration: max(remaining, 60), remainingWhenPaused: 0,
                                   deadline: now.addingTimeInterval(remaining), phase: .running)
        #expect(session.timeLabel(at: now) == expected)
        #expect(session.showsHours(at: now) == (remaining >= 3_600))
    }
}
