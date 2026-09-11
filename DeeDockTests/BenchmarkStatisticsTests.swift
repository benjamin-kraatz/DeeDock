import Foundation
import Testing

struct BenchmarkStatisticsTests {
    @Test("No samples produce no distribution rather than zeros")
    func emptySamples() {
        #expect(BenchmarkDistribution(samples: []) == nil)
        #expect(BenchmarkDistribution(samples: [.nan, .infinity]) == nil)
    }

    @Test("Percentiles use nearest rank and always return an observed sample")
    func nearestRank() throws {
        let distribution = try #require(BenchmarkDistribution(samples: (1...100).map(Double.init).shuffled()))
        #expect(distribution.count == 100)
        #expect(distribution.min == 1)
        #expect(distribution.p50 == 50)
        #expect(distribution.p90 == 90)
        #expect(distribution.p95 == 95)
        #expect(distribution.p99 == 99)
        #expect(distribution.max == 100)
        #expect(distribution.mean == 50.5)
    }

    @Test("With fewer than 100 samples p99 is the maximum")
    func smallSample() throws {
        let distribution = try #require(BenchmarkDistribution(samples: [4, 1, 3, 2]))
        #expect(distribution.p50 == 2)
        #expect(distribution.p95 == 4)
        #expect(distribution.p99 == 4)
    }

    @Test("A single sample is every percentile")
    func singleSample() throws {
        let distribution = try #require(BenchmarkDistribution(samples: [7]))
        #expect([distribution.min, distribution.p50, distribution.p99, distribution.max] == [7, 7, 7, 7])
    }

    @Test("Hitches are callbacks later than 1.5 frames; the ratio counts only the excess")
    func hitchRatio() {
        // 58 on-time 60 Hz frames plus two late ones: 50 ms (+33.3 ms excess) and 30 ms (+13.3 ms).
        let frame = 1_000.0 / 60
        let intervals = Array(repeating: frame, count: 58) + [50, 30]
        let summary = BenchmarkFrameSummary(intervals: intervals, expected: frame)
        #expect(summary.frames == 60)
        #expect(summary.hitches == 2)
        let seconds = intervals.reduce(0, +) / 1_000
        #expect(abs(summary.hitchRatio - (50 + 30 - 2 * frame) / seconds) < 1e-9)
    }

    @Test("Slightly late frames within the threshold are not hitches")
    func jitterIsNotAHitch() {
        let frame = 1_000.0 / 120
        let summary = BenchmarkFrameSummary(intervals: [frame, frame * 1.4, frame], expected: frame)
        #expect(summary.hitches == 0)
        #expect(summary.hitchRatio == 0)
    }

    @Test("Stage reports round-trip through JSON")
    func reportRoundTrip() throws {
        var report = BenchmarkStageReport(stage: "scenarios")
        report.metrics["stackOpen"] = BenchmarkDistribution(samples: [10, 20, 30])
        report.skipped["peekOpen"] = "No running application is in the dock."
        let decoded = try JSONDecoder().decode(BenchmarkStageReport.self, from: JSONEncoder().encode(report))
        #expect(decoded.schema == BenchmarkStageReport.schema)
        #expect(decoded.metrics["stackOpen"]?.p50 == 20)
        #expect(decoded.skipped == report.skipped)
    }

    @Test("Resource summaries turn counters into rates over the sampled window")
    func resourceRates() throws {
        // Two readings of the current process one tenth of a second apart are enough to exercise the math.
        let pid = ProcessInfo.processInfo.processIdentifier
        let first = try #require(ProcessResourceSample(pid: pid))
        Thread.sleep(forTimeInterval: 0.1)
        let last = try #require(ProcessResourceSample(pid: pid))
        let summary = try #require(ProcessResourceSummary(process: "tests", samples: [first, last]))
        #expect(summary.seconds > 0)
        #expect(summary.cpuPercent >= 0)
        #expect(summary.footprintMiB?.count == 2)
        #expect(ProcessResourceSummary(process: "tests", samples: [first]) == nil)
    }
}
