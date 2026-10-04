import Foundation

/// Decides whether a badge scan result replaces the presented snapshot.
///
/// A scan that throws, such as one Accessibility child timeout, keeps the last successful
/// snapshot for `gracePeriod`. After that the badges count as unavailable, so a Dock that stays
/// unresponsive cannot show an old count indefinitely. A successful scan always replaces the
/// snapshot, including an empty one.
nonisolated struct BadgeScanRetention {
    enum Outcome: Equatable {
        /// Present this snapshot. An empty snapshot clears every badge.
        case update([String: BadgeObservation])
        /// Keep presenting the last successful snapshot. Coverage still has a gap.
        case retain
    }

    /// Three periods of the controller's five-second fallback: two failed scans in a row keep
    /// the snapshot, and the third clears it.
    static let gracePeriod: Duration = .seconds(15)

    private var lastSuccess: ContinuousClock.Instant?

    /// - Parameters:
    ///   - snapshot: The reader's result, or `nil` when the scan threw.
    ///   - now: When the result arrived.
    mutating func resolve(_ snapshot: [String: BadgeObservation]?,
                          at now: ContinuousClock.Instant) -> Outcome {
        if let snapshot {
            lastSuccess = now
            return .update(snapshot)
        }
        if let lastSuccess, now - lastSuccess < Self.gracePeriod { return .retain }
        // Later failures stay unavailable until a scan succeeds again.
        lastSuccess = nil
        return .update([:])
    }
}
