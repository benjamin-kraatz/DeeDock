import Foundation

/// The Hold to Delete button's fill, as a function of time.
///
/// Holding fills it left to right in 0.9 s from wherever it was. Releasing early drains it back
/// three times faster. Views sample ``progress(at:)`` in a `TimelineView` while ``isAnimating``;
/// the controller schedules completion from ``remainingHold(at:)``.
nonisolated struct VaporHoldProgress: Equatable, Sendable {
    static let holdDuration: TimeInterval = 0.9
    static let drainDuration: TimeInterval = 0.3

    private(set) var isHolding = false
    /// The fill when the current hold or drain began.
    private var startValue: Double = 0
    private var startDate: Date?

    /// The fill, 0…1, at `date`.
    func progress(at date: Date) -> Double {
        guard let startDate else { return startValue }
        let elapsed = max(date.timeIntervalSince(startDate), 0)
        if isHolding { return min(startValue + elapsed / Self.holdDuration, 1) }
        return max(startValue - elapsed / Self.drainDuration, 0)
    }

    /// True while the fill is changing, so a view needs to redraw.
    func isAnimating(at date: Date) -> Bool {
        if isHolding { return progress(at: date) < 1 }
        return startDate != nil && progress(at: date) > 0
    }

    /// Whether a hold has filled the button. Allows for floating-point error in the elapsed time.
    func isComplete(at date: Date) -> Bool { isHolding && progress(at: date) >= 1 - 1e-9 }

    /// Seconds of holding left until the fill completes.
    func remainingHold(at date: Date) -> TimeInterval {
        (1 - progress(at: date)) * Self.holdDuration
    }

    mutating func press(at date: Date) {
        guard !isHolding else { return }
        startValue = progress(at: date)
        startDate = date
        isHolding = true
    }

    mutating func release(at date: Date) {
        guard isHolding else { return }
        startValue = progress(at: date)
        startDate = date
        isHolding = false
    }

    /// Empties the button at once, after a delete or when the panel closes.
    mutating func reset() {
        self = VaporHoldProgress()
    }
}
