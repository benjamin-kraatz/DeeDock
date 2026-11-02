import Foundation

/// The stretch of time a label describes. The person answers about what the app has been doing, so the window
/// ends at the moment of the question and reaches five minutes back.
nonisolated enum AppHealthLabelWindow {
    static let lookback: TimeInterval = 5 * 60

    /// A prompt's window: from five minutes before it appeared to the moment it appeared.
    static func prompt(shownAt: Date) -> DateInterval {
        DateInterval(start: shownAt.addingTimeInterval(-lookback), end: shownAt)
    }

    /// A manual label's window: from five minutes before the person picked the app to the moment they picked it.
    static func manual(pickedAt: Date) -> DateInterval {
        DateInterval(start: pickedAt.addingTimeInterval(-lookback), end: pickedAt)
    }
}
