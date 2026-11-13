import Foundation
import Testing
@testable import DeeDock

/// `LookoutSyncPacer` over explicit instants: the quiet period, the maximum wait, and the growing minimum gap.
struct LookoutSyncPacerTests {
    private let start = ContinuousClock.now
    private func at(_ seconds: Double) -> ContinuousClock.Instant { start + .milliseconds(Int(seconds * 1_000)) }
    private func seconds(_ instant: ContinuousClock.Instant?) -> Double? {
        guard let instant else { return nil }
        let elapsed = start.duration(to: instant).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    @Test func nothingIsDueWithoutAChange() {
        let pacer = LookoutSyncPacer(timing: .standard())
        #expect(!pacer.isPending && pacer.deadline(filesVisible: false) == nil)
    }

    @Test func aBurstSyncsOnceItGoesQuiet() {
        var pacer = LookoutSyncPacer(timing: .standard())
        pacer.changed(at: at(0))
        pacer.changed(at: at(1))
        pacer.changed(at: at(1.5))
        #expect(seconds(pacer.deadline(filesVisible: false)) == 3.5)
        pacer.synced(at: at(3.5))
        #expect(!pacer.isPending && pacer.deadline(filesVisible: false) == nil)
    }

    @Test func continuousChurnSyncsAfterTheMaximumWait() {
        var pacer = LookoutSyncPacer(timing: .standard())
        for tick in 0...40 { pacer.changed(at: at(Double(tick))) }   // a change every second for 40 s
        #expect(seconds(pacer.deadline(filesVisible: false)) == 30)
    }

    @Test func syncsInQuickSuccessionDoubleTheGapUpToAMinute() {
        var pacer = LookoutSyncPacer(timing: .standard())
        var time = 0.0
        var gaps: [Double] = []
        for _ in 0..<8 {
            pacer.changed(at: at(time))
            let due = seconds(pacer.deadline(filesVisible: false))!
            if let last = seconds(pacer.lastSync) { gaps.append(due - last) }
            pacer.synced(at: at(due))
            time = due + 0.5
        }
        // The quiet period (2.5 s from the change) binds until the gap grows past it.
        #expect(gaps == [2.5, 4, 8, 16, 32, 60, 60])
    }

    @Test func theFilesTabSkipsTheGap() {
        var pacer = LookoutSyncPacer(timing: .standard())
        pacer.changed(at: at(0))
        pacer.synced(at: at(2))
        pacer.changed(at: at(2.5))
        pacer.synced(at: at(4.5))   // within a minute: the gap is 4 s now
        pacer.changed(at: at(5))
        #expect(seconds(pacer.deadline(filesVisible: false)) == 8.5)
        #expect(seconds(pacer.deadline(filesVisible: true)) == 7)
    }

    @Test func fiveQuietMinutesResetTheGap() {
        var pacer = LookoutSyncPacer(timing: .standard())
        var time = 0.0
        for _ in 0..<5 {
            pacer.changed(at: at(time))
            let due = seconds(pacer.deadline(filesVisible: false))!
            pacer.synced(at: at(due))
            time = due + 0.5
        }
        #expect(pacer.gap == .seconds(32))
        pacer.changed(at: at(time + 120))   // two minutes later: the gap stays
        pacer.synced(at: at(time + 122))
        #expect(pacer.gap == .seconds(32))
        pacer.changed(at: at(time + 500))   // over five minutes since the last sync
        pacer.synced(at: at(time + 502))
        #expect(pacer.gap == .seconds(2))
    }
}
