import CoreGraphics
import Foundation

/// JSON written by one benchmark stage. The `benchmarks/` tool merges stages into a run file.
///
/// Also compiled into the `benchmarks/` command-line tool, so it avoids app types and main-actor isolation.
nonisolated struct BenchmarkStageReport: Codable, Sendable {
    static let schema = 1
    var schema = Self.schema
    /// `scenarios`, `launch`, `e2e`, `idle`, or `micro`.
    var stage: String
    /// Latency distributions in milliseconds, keyed by `PerformanceMetric` raw value.
    var metrics: [String: BenchmarkDistribution] = [:]
    /// Frame pacing per scenario, keyed by scenario name.
    var frames: [String: BenchmarkFrameSummary] = [:]
    /// Resource use per process, keyed by `ddock` or `dock`.
    var resources: [String: ProcessResourceSummary] = [:]
    /// Settings that change what a number means, such as auto-hide delays.
    var context: [String: String] = [:]
    /// Scenarios that could not run and why, so a missing row is never silent.
    var skipped: [String: String] = [:]

    init(stage: String) { self.stage = stage }
}

/// Screen positions the end-to-end runner needs to post real input, in Quartz global coordinates
/// (origin at the top-left of the primary display, y down), which is what `CGEvent` expects.
nonisolated struct BenchmarkDockGeometry: Codable, Sendable {
    var displayID: String
    /// Visible dock surface at rest.
    var dock: CGRect
    /// Region whose entry reveals an auto-hidden dock.
    var activationZone: CGRect
    /// Centers of application icons, in dock order.
    var iconCenters: [CGPoint]
    /// Launcher tile, when the dock shows one.
    var launcher: CGRect?
    /// A point well away from the dock, used to let an auto-hidden dock hide again.
    var restingPoint: CGPoint
    var autoHide: Bool
    var revealDelay: Double
    var hideDelay: Double
    var animationDuration: Double
}
