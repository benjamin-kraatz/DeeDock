import Darwin
import Foundation

/// One `proc_pid_rusage` reading. Works for any process owned by the same user, including the system Dock.
///
/// Also compiled into the `benchmarks/` command-line tool, so it avoids app types and main-actor isolation.
nonisolated struct ProcessResourceSample: Sendable {
    /// Seconds since boot, the same clock as `NSEvent.timestamp`.
    var uptime: TimeInterval
    /// The value Activity Monitor shows as Memory.
    var footprintBytes: UInt64
    var cpuSeconds: Double
    /// Package-idle plus interrupt wakeups. A resting dock should cause close to none.
    var wakeups: UInt64
    var energyNanojoules: UInt64

    init?(pid: pid_t) {
        var info = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard status == 0 else { return nil }
        uptime = ProcessInfo.processInfo.systemUptime
        footprintBytes = info.ri_phys_footprint
        // `ri_user_time` and `ri_system_time` are Mach absolute-time ticks, not nanoseconds, on Apple silicon.
        cpuSeconds = Double(info.ri_user_time + info.ri_system_time) * Self.nanosecondsPerTick / 1e9
        wakeups = info.ri_pkg_idle_wkups + info.ri_interrupt_wkups
        energyNanojoules = info.ri_energy_nj
    }

    private static let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()
}

/// Rates and footprint over a series of samples of one process.
nonisolated struct ProcessResourceSummary: Codable, Equatable, Sendable {
    var process: String
    var seconds: Double
    /// Percent of one core, averaged over the window (Activity Monitor's % CPU convention).
    var cpuPercent: Double
    var wakeupsPerSecond: Double
    /// Average power in milliwatts, from the kernel's energy counter. `nil` when the kernel reports none.
    var energyMilliwatts: Double?
    /// Footprint in MiB across the samples.
    var footprintMiB: BenchmarkDistribution?

    init?(process: String, samples: [ProcessResourceSample]) {
        guard let first = samples.first, let last = samples.last, last.uptime > first.uptime else { return nil }
        self.process = process
        seconds = last.uptime - first.uptime
        cpuPercent = (last.cpuSeconds - first.cpuSeconds) / seconds * 100
        wakeupsPerSecond = Double(last.wakeups &- first.wakeups) / seconds
        let energy = last.energyNanojoules &- first.energyNanojoules
        energyMilliwatts = energy > 0 ? Double(energy) / 1e6 / seconds : nil
        footprintMiB = BenchmarkDistribution(samples: samples.map { Double($0.footprintBytes) / 1_048_576 })
    }
}
