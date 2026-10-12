import Foundation

/// A smoothed pace, in units (files, or pages and chunks) per second, from a running count sampled whenever it
/// changes, and the time the rest takes at that pace. Pure, so the smoothing is testable with made-up clocks.
///
/// The index service reports as files finish: images eight at a time, a long PDF after many seconds, so the count
/// moves in uneven steps at uneven times. For its first `warmUpSeconds` and `warmUpUnits`, the pace is the plain
/// average of everything seen, and nothing is reported: a pace from the first few files says little. After that,
/// each new sample moves the pace toward the pace since the last sample by `1 − e^(−Δt/τ)`, an exponential average
/// over about `timeConstant` of reading that weighs a sample by how long it covers, so a burst of eight images
/// doesn't count more than the seconds it took.
///
/// Time that isn't reading doesn't count: `pause()` forgets the last sample, so the gap until reading resumes never
/// becomes a stretch of zero pace, and the pace from before carries on.
nonisolated struct LookoutRateEstimator: Equatable, Sendable {
    /// Reading has to have gone on this long before there's a pace.
    static let warmUpSeconds: TimeInterval = 10
    /// And this many units read.
    static let warmUpUnits = 5
    /// The exponential average's time constant: samples older than about this weigh little.
    static let timeConstant: TimeInterval = 30

    private struct Sample: Equatable, Sendable {
        let time: Date
        let units: Int
    }

    private var last: Sample?
    /// Reading time and units seen since the last `reset`, gaps left out.
    private(set) var observedSeconds: TimeInterval = 0
    private(set) var observedUnits = 0
    private var pace: Double?

    init() {}

    /// The count reached `units` at `time`. A count lower than the last one (the service started a new run) or a
    /// clock that went back starts a new interval without moving the pace.
    mutating func record(_ units: Int, at time: Date) {
        defer { last = Sample(time: time, units: units) }
        guard let last else { return }
        let seconds = time.timeIntervalSince(last.time)
        let read = units - last.units
        guard seconds > 0, read >= 0 else { return }
        let wasWarm = isWarm
        observedSeconds += seconds
        observedUnits += read
        guard wasWarm, let pace else {
            // Warming up, or warm with this sample: the plain average of everything seen.
            self.pace = Double(observedUnits) / observedSeconds
            return
        }
        let weight = 1 - exp(-seconds / Self.timeConstant)
        self.pace = pace + weight * (Double(read) / seconds - pace)
    }

    /// Reading stopped for a while (paused, counting, waiting): the time until it resumes isn't counted.
    mutating func pause() {
        last = nil
    }

    /// A new pass: forget everything.
    mutating func reset() {
        self = LookoutRateEstimator()
    }

    private var isWarm: Bool {
        observedSeconds >= Self.warmUpSeconds && observedUnits >= Self.warmUpUnits
    }

    /// The smoothed pace, or nil while it's too early to say.
    var unitsPerSecond: Double? {
        guard isWarm, let pace, pace > 0 else { return nil }
        return pace
    }

    /// How long `units` take at the smoothed pace, or nil while it's too early to say or nothing is left.
    func timeRemaining(for units: Int) -> TimeInterval? {
        guard units > 0, let pace = unitsPerSecond else { return nil }
        return Double(units) / pace
    }
}
