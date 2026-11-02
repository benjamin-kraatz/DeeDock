import Foundation

/// Which computed samples reach disk, so 30 days of data fit under the size cap. Pure.
///
/// Every app is sampled every tick; a row is written when the app is `active` (busy now, or within
/// `hysteresisTicks` after it last was, so each busy series has a quiet tail), when its footprint moved by
/// `growthBytes` since its last written row (`growth`), or when nothing was written for it in `baselineInterval`
/// (`baseline`, which also writes an app's first sample). Backfill is separate: see `AppHealthHistory`.
nonisolated enum AppHealthWritePolicy {
    static let activeCPUPercent = 2.0
    static let activeWakeupsPerSecond = 20.0
    /// Quiet ticks still written after the last active one.
    static let hysteresisTicks = 3
    /// Footprint change since the last written row that writes a `growth` row: 50 MB.
    static let growthBytes: UInt64 = 50_000_000
    /// Longest gap without a row for an app: 30 minutes.
    static let baselineInterval: TimeInterval = 30 * 60

    /// What the policy remembers per app between ticks.
    struct AppState: Sendable, Equatable {
        /// Quiet ticks since the app was last active; nil until it has been active.
        var ticksSinceActive: Int?
        var lastWrittenFootprint: UInt64?
        var lastWrittenAt: Date?
    }

    /// Whether a sample counts as busy on its own.
    static func isActive(_ sample: AppHealthSample) -> Bool {
        sample.cpuPercent >= activeCPUPercent || sample.wakeupsPerSecond >= activeWakeupsPerSecond
            || (sample.hang.map { $0 != .ok } ?? false)
    }

    /// Decides this tick's row for one app and updates its state.
    ///
    /// - Returns: The reason to write, or nil to keep the sample in memory only.
    static func decide(_ sample: AppHealthSample, state: inout AppState) -> AppHealthWriteReason? {
        let reason: AppHealthWriteReason?
        if isActive(sample) {
            state.ticksSinceActive = 0
            reason = .active
        } else if let quiet = state.ticksSinceActive, quiet < hysteresisTicks {
            state.ticksSinceActive = quiet + 1
            reason = .active
        } else {
            if let quiet = state.ticksSinceActive { state.ticksSinceActive = quiet + 1 }
            if let footprint = state.lastWrittenFootprint, let writtenAt = state.lastWrittenAt {
                let change = sample.mem > footprint ? sample.mem - footprint : footprint - sample.mem
                if change >= growthBytes { reason = .growth }
                else if sample.timestamp.timeIntervalSince(writtenAt) >= baselineInterval { reason = .baseline }
                else { reason = nil }
            } else {
                reason = .baseline
            }
        }
        if reason != nil { noteWritten(sample, state: &state) }
        return reason
    }

    /// Records that a row for `sample` is on disk, such as after a backfill, so growth and baseline measure from
    /// the newest written row.
    static func noteWritten(_ sample: AppHealthSample, state: inout AppState) {
        guard state.lastWrittenAt.map({ sample.timestamp >= $0 }) ?? true else { return }
        state.lastWrittenFootprint = sample.mem
        state.lastWrittenAt = sample.timestamp
    }
}
