import Foundation

/// Decides whether a badge scan result replaces the presented snapshot.
///
/// A scan that throws, such as one Accessibility child timeout, keeps the last successful
/// snapshot for `gracePeriod`. After that the badges count as unavailable, so a Dock that stays
/// unresponsive cannot show an old count indefinitely. A successful scan always replaces the
/// snapshot, including an empty one. Suspension hides the current snapshot without moving this clock.
nonisolated struct BadgeScanRetention {
    enum Outcome: Equatable {
        /// Present this snapshot. An empty snapshot clears every badge.
        case update([String: BadgeObservation])
        /// Keep the last successful snapshot. Coverage still has a gap.
        ///
        /// The associated snapshot is one that ``suspend(keeping:)`` hid. The caller puts it
        /// back on screen. `nil` means the badges are already showing that snapshot.
        case retain([String: BadgeObservation]?)
    }

    /// Three periods of the controller's five-second fallback: two failed scans in a row keep
    /// the snapshot, and the third clears it.
    static let gracePeriod: Duration = .seconds(15)

    private var lastSuccess: ContinuousClock.Instant?
    /// Snapshot hidden by suspension. Only a retain inside the grace period hands it back.
    private var held: [String: BadgeObservation]?

    /// Remembers `snapshot` for a later retain. A second call keeps the first snapshot,
    /// so stacked sleep and lock notifications cannot replace it with an empty one.
    /// The grace clock stays where the last successful scan left it.
    mutating func suspend(keeping snapshot: [String: BadgeObservation]) {
        if held == nil { held = snapshot }
    }

    /// - Parameters:
    ///   - snapshot: The reader's result, or `nil` when the scan threw.
    ///   - now: When the result arrived.
    mutating func resolve(_ snapshot: [String: BadgeObservation]?,
                          at now: ContinuousClock.Instant) -> Outcome {
        if let snapshot {
            lastSuccess = now
            held = nil
            return .update(snapshot)
        }
        if let lastSuccess, now - lastSuccess < Self.gracePeriod {
            let restored = held
            held = nil
            return .retain(restored)
        }
        // Later failures stay unavailable until a scan succeeds again.
        // Drop the hidden snapshot so an expired grace cannot revive it.
        lastSuccess = nil
        held = nil
        return .update([:])
    }
}
