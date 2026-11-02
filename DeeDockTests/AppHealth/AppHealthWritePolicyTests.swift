import Foundation
import Testing
@testable import DeeDock

/// Which samples reach disk: active with a three-tick tail, growth of 50 MB, and a 30-minute baseline.
struct AppHealthWritePolicyTests {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    private func sample(tick: Int, cpu: Double = 0, wakeups: UInt64 = 0, mem: UInt64 = 100_000_000,
                        hang: AppHealthHangResult? = nil) -> AppHealthSample {
        AppHealthSample(app: "com.example.App", kind: .regular, timestamp: start.addingTimeInterval(Double(tick) * 20),
                        interval: 20, cpuMain: cpu, cpuHelpers: 0, mem: mem, memMain: mem, procs: 1,
                        wakeups: wakeups, energy: nil, frontmost: false, hang: hang)
    }

    private func run(_ samples: [AppHealthSample]) -> [AppHealthWriteReason?] {
        var state = AppHealthWritePolicy.AppState()
        return samples.map { AppHealthWritePolicy.decide($0, state: &state) }
    }

    @Test("An app's first sample is a baseline row")
    func firstSampleIsBaseline() {
        #expect(run([sample(tick: 0)]) == [.baseline])
    }

    @Test("A busy tick is written, then three quiet ticks, then nothing")
    func hysteresisTail() {
        // 0.5 core-seconds in 20 s is 2.5 % CPU, just over the 2 % threshold.
        let reasons = run([sample(tick: 0), sample(tick: 1, cpu: 0.5)] + (2...6).map { sample(tick: $0) })
        #expect(reasons == [.baseline, .active, .active, .active, .active, nil, nil])
    }

    @Test("A busy tick inside the tail restarts it")
    func tailRestarts() {
        let reasons = run([sample(tick: 0), sample(tick: 1, cpu: 4), sample(tick: 2), sample(tick: 3, cpu: 4)]
                          + (4...8).map { sample(tick: $0) })
        #expect(reasons == [.baseline, .active, .active, .active, .active, .active, .active, nil, nil])
    }

    @Test("Just under 2 % CPU and 20 wake-ups per second is quiet; a failed check is active")
    func thresholds() {
        #expect(run([sample(tick: 0), sample(tick: 1, cpu: 0.39)]) == [.baseline, nil])
        #expect(run([sample(tick: 0), sample(tick: 1, wakeups: 399)]) == [.baseline, nil])
        #expect(run([sample(tick: 0), sample(tick: 1, wakeups: 400)]) == [.baseline, .active])
        #expect(run([sample(tick: 0), sample(tick: 1, hang: .ok)]) == [.baseline, nil])
        #expect(run([sample(tick: 0), sample(tick: 1, hang: .timeout)]) == [.baseline, .active])
        #expect(run([sample(tick: 0), sample(tick: 1, hang: .error)]) == [.baseline, .active])
    }

    @Test("A 50 MB footprint change since the last written row writes a growth row, in either direction")
    func growth() {
        let reasons = run([sample(tick: 0, mem: 100_000_000), sample(tick: 1, mem: 140_000_000),
                           sample(tick: 2, mem: 150_000_000), sample(tick: 3, mem: 170_000_000),
                           sample(tick: 4, mem: 100_000_000)])
        // Growth measures from the last written row: 100 → 150 MB, then 150 → 100 MB.
        #expect(reasons == [.baseline, nil, .growth, nil, .growth])
    }

    @Test("A quiet app gets a baseline row every 30 minutes")
    func baselineInterval() {
        let ticks = [0, 1, 89, 90, 91, 180]
        let reasons = run(ticks.map { sample(tick: $0) })
        // 90 ticks of 20 s is 30 minutes.
        #expect(reasons == [.baseline, nil, nil, .baseline, nil, .baseline])
    }

    @Test("A backfilled row resets growth and baseline to the newest written row")
    func noteWritten() {
        var state = AppHealthWritePolicy.AppState()
        _ = AppHealthWritePolicy.decide(sample(tick: 0, mem: 100_000_000), state: &state)
        AppHealthWritePolicy.noteWritten(sample(tick: 80, mem: 160_000_000), state: &state)
        // An older backfilled sample does not move the reference back.
        AppHealthWritePolicy.noteWritten(sample(tick: 10, mem: 100_000_000), state: &state)
        #expect(AppHealthWritePolicy.decide(sample(tick: 91, mem: 170_000_000), state: &state) == nil)
        #expect(AppHealthWritePolicy.decide(sample(tick: 170, mem: 170_000_000), state: &state) == .baseline)
    }
}
