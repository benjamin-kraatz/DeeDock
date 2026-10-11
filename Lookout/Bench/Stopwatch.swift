import Foundation

/// Wall-clock timing on the monotonic clock.
enum Stopwatch {
    /// Runs `body` once and returns its result with the seconds it took.
    static func time<T>(_ body: () throws -> T) rethrows -> (value: T, seconds: Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
    }
}

/// A set of timings, summarized the way the decision gate reads them.
struct Samples {
    /// Ascending.
    let sorted: [Double]

    init(_ values: [Double]) {
        precondition(!values.isEmpty, "no samples")
        sorted = values.sorted()
    }

    var median: Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The nearest-rank percentile: the smallest sample with at least `percent` % of the samples at or below it
    /// (the 29th of 30 for p95).
    func percentile(_ percent: Double) -> Double {
        let rank = Int((percent / 100 * Double(sorted.count)).rounded(.up))
        return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
    }

    var min: Double { sorted[0] }
    var max: Double { sorted[sorted.count - 1] }
}
