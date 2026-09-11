import Foundation

/// Summary of one metric's raw samples. Values keep the unit of the input, milliseconds for latency.
///
/// Also compiled into the `benchmarks/` command-line tool, so it avoids app types and main-actor isolation.
nonisolated struct BenchmarkDistribution: Codable, Equatable, Sendable {
    var count: Int
    var min: Double
    var p50: Double
    var p90: Double
    var p95: Double
    var p99: Double
    var max: Double
    var mean: Double

    /// Returns `nil` for an empty sample set rather than inventing zeros that would read as a result.
    init?(samples: [Double]) {
        let sorted = samples.filter(\.isFinite).sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        count = sorted.count
        min = first
        max = last
        mean = sorted.reduce(0, +) / Double(sorted.count)
        p50 = Self.percentile(0.50, sorted: sorted)
        p90 = Self.percentile(0.90, sorted: sorted)
        p95 = Self.percentile(0.95, sorted: sorted)
        p99 = Self.percentile(0.99, sorted: sorted)
    }

    /// Nearest-rank percentile: always an observed sample, never an interpolation between two.
    /// With fewer than 100 samples p99 is therefore the maximum, which is the honest answer.
    static func percentile(_ fraction: Double, sorted: [Double]) -> Double {
        precondition(!sorted.isEmpty && (0...1).contains(fraction))
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(0, Swift.min(sorted.count - 1, rank - 1))]
    }
}

/// Main-thread frame pacing observed through a display link while a scenario animates.
///
/// A late callback means the main thread could not service the display link on time. This is a proxy for
/// app-side hitches; render-server hitches need the Instruments Animation Hitches template.
nonisolated struct BenchmarkFrameSummary: Codable, Equatable, Sendable {
    var frames: Int
    var seconds: Double
    /// Callbacks later than 1.5 frame durations after the previous one.
    var hitches: Int
    /// Milliseconds spent beyond the expected frame duration, per second of observation. Apple's
    /// guidance treats under 5 ms/s as good and over 10 ms/s as noticeable.
    var hitchRatio: Double
    var intervals: BenchmarkDistribution?

    init(intervals: [Double], expected: Double) {
        frames = intervals.count
        seconds = intervals.reduce(0, +) / 1_000
        let late = intervals.filter { $0 > expected * 1.5 }
        hitches = late.count
        hitchRatio = seconds > 0 ? late.map { $0 - expected }.reduce(0, +) / seconds : 0
        self.intervals = BenchmarkDistribution(samples: intervals)
    }
}
