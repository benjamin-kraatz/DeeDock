import Foundation

/// Converts `rusage_info` time fields, which are mach absolute time units rather than nanoseconds.
///
/// On Apple Silicon the timebase is 125/3 (one unit ≈ 41.7 ns); on Intel it is 1/1. Read it once with
/// `mach_timebase_info` and keep it.
nonisolated struct AppHealthMachTimebase: Sendable, Equatable {
    let numerator: UInt32
    let denominator: UInt32

    static func current() -> AppHealthMachTimebase {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return AppHealthMachTimebase(numerator: 1, denominator: 1)
        }
        return AppHealthMachTimebase(numerator: info.numer, denominator: info.denom)
    }

    func seconds(_ units: UInt64) -> Double {
        Double(units) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

/// One process's cumulative counters, as `proc_pid_rusage` reports them, converted to usable units.
nonisolated struct AppHealthProcessCounters: Sendable, Equatable {
    /// User plus system CPU time since the process started, in seconds.
    var cpuSeconds: Double
    /// Package idle wake-ups since the process started.
    var idleWakeups: UInt64
    /// Energy since the process started, in nanojoules. Zero means the kernel reports none.
    var energy: UInt64

    static let zero = AppHealthProcessCounters(cpuSeconds: 0, idleWakeups: 0, energy: 0)
}

/// What one process contributes to one tick.
nonisolated enum AppHealthDeltaMath {
    /// The counters a process accumulated since the previous tick.
    ///
    /// - A process seen at the previous tick contributes `current − previous`, clamped at zero so a counter that
    ///   moves backwards never yields a negative or wrapped value.
    /// - A process first seen now that started after the previous tick contributes everything it accumulated:
    ///   its whole life fell inside the interval.
    /// - A process first seen now that started earlier contributes nothing this tick. Its counters become the
    ///   baseline. This covers the first tick after a resume and processes newly attributed to an app.
    ///
    /// - Parameters:
    ///   - startedAt: The process start, `ri_proc_start_abstime`, in mach absolute time units.
    ///   - previousTickAt: When the previous tick read its counters, in the same units; nil on a baseline tick.
    static func delta(current: AppHealthProcessCounters, previous: AppHealthProcessCounters?,
                      startedAt: UInt64, previousTickAt: UInt64?) -> AppHealthProcessCounters {
        if let previous {
            return AppHealthProcessCounters(
                cpuSeconds: max(0, current.cpuSeconds - previous.cpuSeconds),
                idleWakeups: current.idleWakeups >= previous.idleWakeups ? current.idleWakeups - previous.idleWakeups : 0,
                energy: current.energy >= previous.energy ? current.energy - previous.energy : 0)
        }
        guard let previousTickAt, startedAt > previousTickAt else { return .zero }
        return current
    }
}

/// One app's processes added up over one tick.
nonisolated struct AppHealthAppUsage: Sendable, Equatable {
    var cpuMain: Double = 0
    var cpuHelpers: Double = 0
    var mem: UInt64 = 0
    var memMain: UInt64 = 0
    var procs = 0
    var wakeups: UInt64 = 0
    /// Nil until a process reports energy, so an app whose processes all report zero stays "unavailable".
    var energy: UInt64?

    var cpu: Double { cpuMain + cpuHelpers }

    /// Adds one process.
    ///
    /// - Parameters:
    ///   - delta: The process's share of this tick (see `AppHealthDeltaMath`).
    ///   - footprint: The process's current physical footprint, in bytes.
    ///   - reportsEnergy: Whether the kernel reports any energy for this process (its cumulative value is
    ///     non-zero). An app's energy is nil only when none of its processes do.
    ///   - isMain: The process is the app's main process rather than a helper.
    mutating func add(_ delta: AppHealthProcessCounters, footprint: UInt64, reportsEnergy: Bool, isMain: Bool) {
        if isMain {
            cpuMain += delta.cpuSeconds
            memMain &+= footprint
        } else {
            cpuHelpers += delta.cpuSeconds
        }
        mem &+= footprint
        procs += 1
        wakeups &+= delta.idleWakeups
        if reportsEnergy { energy = (energy ?? 0) &+ delta.energy }
    }
}
