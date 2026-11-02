import Foundation

/// One app's resource use over one tick, computed in memory every tick for every watched app.
///
/// Only some samples are written (see `AppHealthWritePolicy`); all of them stay in the controller's ten-minute
/// history so a later label can backfill its window. Values are exact here and rounded only when a
/// `AppHealthSampleRecord` is made from them.
nonisolated struct AppHealthSample: Sendable, Equatable {
    /// The bundle identifier. App identity is never anything else.
    let app: String
    let kind: AppHealthAppKind
    /// When the tick that produced this sample ran.
    let timestamp: Date
    /// Seconds actually elapsed since the previous tick.
    let interval: Double
    /// CPU time of the main process(es) over the interval, in core-seconds.
    let cpuMain: Double
    /// CPU time of attributed helper processes over the interval, in core-seconds.
    let cpuHelpers: Double
    /// Sum of the physical footprints of every attributed process, in bytes.
    let mem: UInt64
    /// Physical footprint of the main process(es), in bytes.
    let memMain: UInt64
    /// Attributed processes, the main process included.
    let procs: Int
    /// Package idle wake-ups over the interval.
    let wakeups: UInt64
    /// Energy over the interval in nanojoules, or nil when the kernel reports none for this app's processes.
    let energy: UInt64?
    /// Whether the app was frontmost when the tick ran.
    var frontmost: Bool
    /// The responsiveness check this tick, or nil when the app was not checked.
    var hang: AppHealthHangResult?
    /// How long that check took, in milliseconds.
    var hangMs: Int?

    /// CPU time over the interval, in core-seconds.
    var cpu: Double { cpuMain + cpuHelpers }

    /// CPU use as Activity Monitor shows it: 100 is one core fully busy.
    var cpuPercent: Double { interval > 0 ? cpu / interval * 100 : 0 }

    var wakeupsPerSecond: Double { interval > 0 ? Double(wakeups) / interval : 0 }

    var load: AppHealthLoad { AppHealthLoad(cpuMain: cpuMain, cpuHelpers: cpuHelpers) }
}

/// The rounding App Health applies when it writes numbers, so files stay small and diffs stay readable.
nonisolated enum AppHealthRounding {
    /// Seconds and core-seconds to the millisecond.
    static func seconds(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
    /// Percentages and rates to one decimal.
    static func tenths(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    /// Unix time in seconds with millisecond precision.
    static func timestamp(_ date: Date) -> Double { seconds(date.timeIntervalSince1970) }
}
