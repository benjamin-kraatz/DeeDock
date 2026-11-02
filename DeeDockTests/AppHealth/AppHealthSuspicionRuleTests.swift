import Foundation
import Testing
@testable import DeeDock

/// The suspicion rule's thresholds, windows, and reasons, over synthetic 20-second histories.
struct AppHealthSuspicionRuleTests {
    private let end = Date(timeIntervalSince1970: 1_793_000_000)

    /// One sample `ticksBefore` ticks before `end`.
    private func sample(ticksBefore: Int, cpuPercent: Double = 0, mem: UInt64 = 500_000_000,
                        wakeupsPerSecond: Double = 0, frontmost: Bool = false,
                        hang: AppHealthHangResult? = nil) -> AppHealthSample {
        AppHealthSample(app: "com.example.App", kind: .regular,
                        timestamp: end.addingTimeInterval(-20 * Double(ticksBefore)), interval: 20,
                        cpuMain: cpuPercent * 20 / 100, cpuHelpers: 0, mem: mem, memMain: mem, procs: 1,
                        wakeups: UInt64(wakeupsPerSecond * 20), energy: nil, frontmost: frontmost, hang: hang)
    }

    /// `count` consecutive ticks ending at `end`, oldest first.
    private func series(_ count: Int, _ make: (Int) -> AppHealthSample) -> [AppHealthSample] {
        (0..<count).reversed().map(make)
    }

    @Test("A background spin over 3 minutes is suspicious with cpu and background")
    func backgroundSpin() {
        let history = series(9) { sample(ticksBefore: $0, cpuPercent: 90) }
        let result = AppHealthSuspicionRule.evaluate(history, idleSeconds: 0)
        #expect(result.verdict == .suspicious)
        #expect(result.reasons == [.cpu, .background])
        #expect(result.evidence.meanCPUPercent == 90)
        #expect(result.evidence.shortWindowSeconds == 180)
    }

    @Test("CPU just under 80 % is ordinary heavy use, not a spin")
    func belowSpinThreshold() {
        let history = series(9) { sample(ticksBefore: $0, cpuPercent: 79.9) }
        let result = AppHealthSuspicionRule.evaluate(history, idleSeconds: 0)
        #expect(result.verdict == .ordinary)
        #expect(result.reasons.isEmpty)
    }

    @Test("A frontmost spin needs the person to be away")
    func frontmostSpin() {
        let history = series(9) { sample(ticksBefore: $0, cpuPercent: 120, frontmost: $0 == 4) }
        #expect(AppHealthSuspicionRule.evaluate(history, idleSeconds: 179).verdict == .ordinary)
        let away = AppHealthSuspicionRule.evaluate(history, idleSeconds: 180)
        #expect(away.verdict == .suspicious)
        #expect(away.reasons == [.cpu, .idleUser])
    }

    @Test("The 3-minute window needs all nine ticks, without gaps")
    func shortWindowComplete() {
        let eight = series(8) { sample(ticksBefore: $0, cpuPercent: 200) }
        #expect(AppHealthSuspicionRule.evaluate(eight, idleSeconds: 0).verdict == .none)

        // Tick 5 is missing: the app was not sampled then.
        let gapped = series(10) { sample(ticksBefore: $0, cpuPercent: 200) }.filter {
            $0.timestamp != end.addingTimeInterval(-100)
        }
        #expect(AppHealthSuspicionRule.evaluate(gapped, idleSeconds: 0).verdict == .none)
    }

    @Test("Ordinary heavy use starts at 40 % mean CPU")
    func ordinaryThreshold() {
        let busy = series(9) { sample(ticksBefore: $0, cpuPercent: 40, frontmost: true) }
        #expect(AppHealthSuspicionRule.evaluate(busy, idleSeconds: 0).verdict == .ordinary)
        let quiet = series(9) { sample(ticksBefore: $0, cpuPercent: 39.9, frontmost: true) }
        #expect(AppHealthSuspicionRule.evaluate(quiet, idleSeconds: 0).verdict == .none)
    }

    @Test("Steady memory growth of 1.3× and 400 MB over 10 minutes is suspicious")
    func memoryGrowth() {
        // 1.0 GB to 1.5 GB in 29 equal steps.
        let growing = series(30) { sample(ticksBefore: $0, mem: 1_000_000_000 + UInt64(29 - $0) * 500_000_000 / 29) }
        let result = AppHealthSuspicionRule.evaluate(growing, idleSeconds: 0)
        #expect(result.verdict == .suspicious)
        #expect(result.reasons.contains(.memory))
        #expect(result.evidence.memoryGrowth == 500_000_000)
    }

    @Test("Memory growth below 400 MB, below 1.3×, or mostly falling is not suspicious")
    func memoryGrowthThresholds() {
        let small = series(30) { sample(ticksBefore: $0, mem: 1_000_000_000 + UInt64(29 - $0) * 350_000_000 / 29) }
        #expect(!AppHealthSuspicionRule.evaluate(small, idleSeconds: 0).reasons.contains(.memory))

        let lowRatio = series(30) { sample(ticksBefore: $0, mem: 2_000_000_000 + UInt64(29 - $0) * 500_000_000 / 29) }
        #expect(!AppHealthSuspicionRule.evaluate(lowRatio, idleSeconds: 0).reasons.contains(.memory))

        // Ends 600 MB higher, but every other step falls: half the steps decrease.
        let zigzag = series(30) { index -> AppHealthSample in
            let step = UInt64(29 - index)
            return sample(ticksBefore: index, mem: 1_000_000_000 + step * 40_000_000 - (step % 2 == 1 ? 50_000_000 : 0))
        }
        let zigzagResult = AppHealthSuspicionRule.evaluate(zigzag, idleSeconds: 0)
        #expect((zigzagResult.evidence.memoryGrowth ?? 0) >= 400_000_000)
        #expect(!zigzagResult.reasons.contains(.memory))
    }

    @Test("A wake-up storm counts only in the background")
    func wakeups() {
        let background = series(9) { sample(ticksBefore: $0, wakeupsPerSecond: 500) }
        let result = AppHealthSuspicionRule.evaluate(background, idleSeconds: 0)
        #expect(result.verdict == .suspicious)
        #expect(result.reasons == [.background, .wakeups])

        let front = series(9) { sample(ticksBefore: $0, wakeupsPerSecond: 500, frontmost: $0 == 0) }
        #expect(AppHealthSuspicionRule.evaluate(front, idleSeconds: 0).verdict == .none)

        let slow = series(9) { sample(ticksBefore: $0, wakeupsPerSecond: 399) }
        #expect(AppHealthSuspicionRule.evaluate(slow, idleSeconds: 0).verdict == .none)
    }

    @Test("Two timed-out checks in a row, the latest this tick, are a hang")
    func hang() {
        let failing = [sample(ticksBefore: 2, hang: .timeout), sample(ticksBefore: 1), sample(ticksBefore: 0, hang: .timeout)]
        let result = AppHealthSuspicionRule.evaluate(failing, idleSeconds: 0)
        #expect(result.verdict == .suspicious)
        #expect(result.reasons == [.hang])

        let once = [sample(ticksBefore: 1, hang: .ok), sample(ticksBefore: 0, hang: .timeout)]
        #expect(AppHealthSuspicionRule.evaluate(once, idleSeconds: 0).verdict == .none)

        let recovered = [sample(ticksBefore: 2, hang: .timeout), sample(ticksBefore: 1, hang: .timeout),
                         sample(ticksBefore: 0, hang: .ok)]
        #expect(AppHealthSuspicionRule.evaluate(recovered, idleSeconds: 0).verdict == .none)

        let stale = [sample(ticksBefore: 2, hang: .timeout), sample(ticksBefore: 1, hang: .timeout),
                     sample(ticksBefore: 0)]
        #expect(AppHealthSuspicionRule.evaluate(stale, idleSeconds: 0).verdict == .none)
    }

    @Test("Reasons list every flag that held, in schema order")
    func everyReason() {
        let history = series(30) { index -> AppHealthSample in
            sample(ticksBefore: index, cpuPercent: 150, mem: 1_000_000_000 + UInt64(29 - index) * 30_000_000,
                   wakeupsPerSecond: 800, hang: index < 2 ? .timeout : nil)
        }
        let result = AppHealthSuspicionRule.evaluate(history, idleSeconds: 600)
        #expect(result.reasons == [.cpu, .background, .idleUser, .memory, .wakeups, .hang])
    }

    @Test("Candidates carry the trigger: rule for suspicious apps, ordinary for busy ones")
    func candidates() {
        let spin = series(9) { sample(ticksBefore: $0, cpuPercent: 90) }
        let rule = AppHealthPromptCandidate.evaluate(app: "a", kind: .regular, history: spin, idleSeconds: 0)
        #expect(rule?.trigger == .rule)
        let busy = series(9) { sample(ticksBefore: $0, cpuPercent: 50, frontmost: true) }
        let ordinary = AppHealthPromptCandidate.evaluate(app: "a", kind: .regular, history: busy, idleSeconds: 0)
        #expect(ordinary?.trigger == .ordinary)
        #expect(ordinary?.reasons.isEmpty == true)
        let idle = series(9) { sample(ticksBefore: $0) }
        #expect(AppHealthPromptCandidate.evaluate(app: "a", kind: .regular, history: idle, idleSeconds: 0) == nil)
    }
}
