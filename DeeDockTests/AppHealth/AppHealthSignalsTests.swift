import Foundation
import Testing
@testable import DeeDock

/// Termination signals from history, responsiveness-check candidates, and crash-report matching.
struct AppHealthSignalsTests {
    private let end = Date(timeIntervalSince1970: 1_793_000_000)

    private func sample(secondsBefore: Double, cpu: Double, frontmost: Bool = false,
                        hang: AppHealthHangResult? = nil) -> AppHealthSample {
        AppHealthSample(app: "com.example.App", kind: .regular, timestamp: end.addingTimeInterval(-secondsBefore),
                        interval: 20, cpuMain: cpu, cpuHelpers: 0, mem: 0, memMain: 0, procs: 1, wakeups: 0,
                        energy: nil, frontmost: frontmost, hang: hang)
    }

    @Test("Heavy use and front time count only within the last two minutes")
    func terminationWindow() {
        // 20 core-seconds per 20 s is 100 %; the busy tick is outside the window.
        let history = [sample(secondsBefore: 200, cpu: 20, frontmost: true),
                       sample(secondsBefore: 100, cpu: 8), sample(secondsBefore: 20, cpu: 12)]
        let result = AppHealthTerminationSignals.evaluate(history, terminatedAt: end)
        // Mean of 40 % and 60 % is 50 %.
        #expect(result.heavyBefore)
        #expect(!result.frontmostRecently)
        #expect(!result.hangFailing)
    }

    @Test("Hang failing follows the last check, not any check")
    func hangFailing() {
        let failingThenOK = [sample(secondsBefore: 60, cpu: 0, hang: .timeout), sample(secondsBefore: 40, cpu: 0, hang: .ok),
                             sample(secondsBefore: 20, cpu: 0)]
        #expect(!AppHealthTerminationSignals.evaluate(failingThenOK, terminatedAt: end).hangFailing)
        let okThenFailing = [sample(secondsBefore: 60, cpu: 0, hang: .ok), sample(secondsBefore: 40, cpu: 0, hang: .timeout)]
        #expect(AppHealthTerminationSignals.evaluate(okThenFailing, terminatedAt: end).hangFailing)
        #expect(!AppHealthTerminationSignals.evaluate([], terminatedAt: end).heavyBefore)
    }

    @Test("Checks go to regular apps that are frontmost, busy, or timed out last time, at most four")
    func hangCandidates() {
        typealias Candidate = AppHealthHangCandidates.Candidate
        let candidates = [
            Candidate(app: "front", kind: .regular, cpuPercent: 1, frontmost: true),
            Candidate(app: "busy60", kind: .regular, cpuPercent: 60, frontmost: false),
            Candidate(app: "busy90", kind: .regular, cpuPercent: 90, frontmost: false),
            Candidate(app: "failed", kind: .regular, cpuPercent: 0, frontmost: false),
            Candidate(app: "agent", kind: .accessory, cpuPercent: 99, frontmost: false),
            Candidate(app: "idle", kind: .regular, cpuPercent: 49.9, frontmost: false),
            Candidate(app: "busy50", kind: .regular, cpuPercent: 50, frontmost: false),
        ]
        let selected = AppHealthHangCandidates.select(candidates, failedLastCheck: ["failed"])
        #expect(selected == ["front", "failed", "busy90", "busy60"])
    }

    @Test("A crash report matches by executable name, extension, and time")
    func crashReportMatching() {
        let since = end.addingTimeInterval(-10)
        #expect(AppHealthCrashReportLookup.matches(fileName: "Builder-2026-11-02-101500.ips", modified: end,
                                                   executableName: "Builder", since: since))
        #expect(!AppHealthCrashReportLookup.matches(fileName: "Builder-2026-11-02-101500.ips",
                                                    modified: since.addingTimeInterval(-1),
                                                    executableName: "Builder", since: since))
        #expect(!AppHealthCrashReportLookup.matches(fileName: "BuilderHelper-2026-11-02.ips", modified: end,
                                                    executableName: "Builder", since: since))
        #expect(!AppHealthCrashReportLookup.matches(fileName: "Builder-2026-11-02.diag", modified: end,
                                                    executableName: "Builder", since: since))
        #expect(!AppHealthCrashReportLookup.matches(fileName: "Builder-x.ips", modified: nil,
                                                    executableName: "Builder", since: since))
    }
}
