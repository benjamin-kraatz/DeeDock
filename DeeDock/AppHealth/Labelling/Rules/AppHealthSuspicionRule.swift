import Foundation

/// The rule that decides when an app looks like it is misbehaving, and when it is merely busy enough to be asked
/// about as an ordinary example.
///
/// Pure: it reads one app's in-memory history and the current idle time, nothing else. Callers exclude DOKK itself
/// and apps on the "Don't ask" list before evaluating. Every threshold lives in `Thresholds` and is mirrored in
/// `docs/APP-HEALTH.md` (Suspicion rule); changing one changes what the training data is asked about.
nonisolated enum AppHealthSuspicionRule {
    /// The rule's thresholds, in one place.
    enum Thresholds {
        /// Ticks in the short window: 3 minutes of 20-second ticks.
        static let shortWindowTicks = 9
        /// Ticks in the long window used for memory growth: 10 minutes, the whole in-memory history.
        static let longWindowTicks = AppHealthHistory.capacity
        /// Two consecutive samples further apart than this mean a tick is missing (the app was not running, or
        /// sampling paused), so a window that contains such a gap is not "all present".
        static let maximumTickGap: TimeInterval = 30
        /// `cpu`: mean CPU over the short window, 100 being one core.
        static let spinCPUPercent: Double = 80
        /// `idleUser`: seconds since the last input.
        static let idleUserSeconds = 180
        /// `memory`: the footprint now is at least this multiple of the footprint at the start of the long window…
        static let memoryGrowthRatio: Double = 1.3
        /// …and at least this many bytes (400 decimal megabytes) larger…
        static let memoryGrowthBytes: UInt64 = 400_000_000
        /// …and at least this share of tick-to-tick steps did not decrease.
        static let memoryNonDecreasingShare: Double = 0.8
        /// `wakeups`: mean idle wake-ups per second over the short window.
        static let wakeupsPerSecond: Double = 400
        /// `hang`: this many most recent responsiveness checks timed out, the latest one in this tick.
        static let hangTimeouts = 2
        /// Ordinary heavy use: mean CPU over the short window.
        static let ordinaryCPUPercent: Double = 40
    }

    /// Evaluates one app.
    ///
    /// - Parameters:
    ///   - history: The app's samples, oldest first, ending with the tick being evaluated.
    ///   - idleSeconds: Seconds since the last keyboard, mouse, or trackpad input, at that tick.
    /// - Returns: Whether the app is suspicious, an ordinary heavy-use candidate, or neither, with the numbers a
    ///   prompt's reason line shows.
    static func evaluate(_ history: [AppHealthSample], idleSeconds: Int) -> AppHealthSuspicion {
        var evidence = AppHealthSuspicionEvidence()
        var flags: Set<AppHealthPromptReason> = []

        let short = contiguousTail(history, count: Thresholds.shortWindowTicks)
        if let short {
            let meanCPU = short.map(\.cpuPercent).reduce(0, +) / Double(short.count)
            let meanWakeups = short.map(\.wakeupsPerSecond).reduce(0, +) / Double(short.count)
            evidence.meanCPUPercent = meanCPU
            evidence.meanWakeupsPerSecond = meanWakeups
            evidence.shortWindowSeconds = short.map(\.interval).reduce(0, +)
            if meanCPU >= Thresholds.spinCPUPercent { flags.insert(.cpu) }
            if !short.contains(where: \.frontmost) { flags.insert(.background) }
            if meanWakeups >= Thresholds.wakeupsPerSecond, flags.contains(.background) { flags.insert(.wakeups) }
        }
        if idleSeconds >= Thresholds.idleUserSeconds { flags.insert(.idleUser) }

        if let long = contiguousTail(history, count: Thresholds.longWindowTicks),
           let first = long.first, let last = long.last {
            let growth = Int64(last.mem) - Int64(first.mem)
            evidence.memoryGrowth = growth
            evidence.longWindowSeconds = last.timestamp.timeIntervalSince(first.timestamp) + first.interval
            let steps = zip(long, long.dropFirst())
            let nonDecreasing = steps.filter { $0.1.mem >= $0.0.mem }.count
            let share = Double(nonDecreasing) / Double(long.count - 1)
            if Double(last.mem) >= Thresholds.memoryGrowthRatio * Double(first.mem),
               growth >= Int64(Thresholds.memoryGrowthBytes),
               share >= Thresholds.memoryNonDecreasingShare {
                flags.insert(.memory)
            }
        }

        let checks = history.compactMap(\.hang).suffix(Thresholds.hangTimeouts)
        if history.last?.hang == .timeout, checks.count == Thresholds.hangTimeouts,
           checks.allSatisfy({ $0 == .timeout }) {
            flags.insert(.hang)
        }

        let spin = flags.contains(.cpu) && (flags.contains(.background) || flags.contains(.idleUser))
        let suspicious = spin || flags.contains(.memory) || flags.contains(.wakeups) || flags.contains(.hang)
        if suspicious {
            // Every flag that held, in the schema's order, so `reasons` reads the same in every record.
            let reasons = AppHealthPromptReason.allCases.filter { flags.contains($0) }
            return AppHealthSuspicion(verdict: .suspicious, reasons: reasons, evidence: evidence)
        }
        if let cpu = evidence.meanCPUPercent, cpu >= Thresholds.ordinaryCPUPercent {
            return AppHealthSuspicion(verdict: .ordinary, reasons: [], evidence: evidence)
        }
        return AppHealthSuspicion(verdict: .none, reasons: [], evidence: evidence)
    }

    /// The last `count` samples when all of them are present: no two consecutive samples further apart than
    /// `maximumTickGap`. Nil when the history is shorter or has a gap in that tail.
    static func contiguousTail(_ history: [AppHealthSample], count: Int) -> [AppHealthSample]? {
        guard count > 0, history.count >= count else { return nil }
        let tail = Array(history.suffix(count))
        for (earlier, later) in zip(tail, tail.dropFirst())
        where later.timestamp.timeIntervalSince(earlier.timestamp) > Thresholds.maximumTickGap {
            return nil
        }
        return tail
    }
}

/// The outcome of `AppHealthSuspicionRule.evaluate(_:idleSeconds:)` for one app.
nonisolated struct AppHealthSuspicion: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        /// The suspicion rule held: a spin, memory growth, a wake-up storm, or a hang.
        case suspicious
        /// Busy, but not suspicious: a candidate for an ordinary prompt.
        case ordinary
        case none
    }

    let verdict: Verdict
    /// Every flag that held, for a suspicious app. Empty otherwise.
    let reasons: [AppHealthPromptReason]
    let evidence: AppHealthSuspicionEvidence
}

/// The numbers behind a verdict, so a prompt can say what it saw. Nil where a window was not complete.
nonisolated struct AppHealthSuspicionEvidence: Equatable, Sendable {
    /// Mean CPU over the short window; 100 is one core.
    var meanCPUPercent: Double?
    /// Seconds the short window covers, about 180.
    var shortWindowSeconds: Double?
    /// Footprint change over the long window, in bytes.
    var memoryGrowth: Int64?
    /// Seconds the long window covers, about 600.
    var longWindowSeconds: Double?
    /// Mean idle wake-ups per second over the short window.
    var meanWakeupsPerSecond: Double?
}
