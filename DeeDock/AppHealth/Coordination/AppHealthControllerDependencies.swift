import Foundation

/// The services `AppHealthController` drives. `live()` wires the real ones; tests inject fakes so lifecycle and
/// cancellation can be exercised without libproc, Accessibility, the file system, or real sleeps.
struct AppHealthControllerDependencies {
    var sampler: any AppHealthSampling
    var store: any AppHealthRecording
    var hangChecker: any AppHealthHangChecking
    var crashReports: any AppHealthCrashReportLooking
    var observers: any AppHealthSystemObserving
    /// Builds a tick's snapshot from the running apps and cheap system signals. Main actor, no I/O.
    var snapshot: @MainActor (Date, AppHealthPowerSource, AppHealthThermalState) -> AppHealthSystemSnapshot
    var powerSource: @MainActor () -> AppHealthPowerSource
    var thermalState: @MainActor () -> AppHealthThermalState
    /// Waits for the next tick. Throws when the sampling task is cancelled.
    var waitForNextTick: @Sendable () async throws -> Void
    /// Waits before looking for a crash report, giving macOS time to write it. Throws when cancelled.
    var crashReportDelay: @Sendable () async throws -> Void
    var now: @MainActor () -> Date
    /// DOKK's version for the export manifest, such as `0.24.3 (74)`.
    var appVersion: @MainActor () -> String

    /// The production services.
    static func live() -> AppHealthControllerDependencies {
        AppHealthControllerDependencies(
            sampler: AppHealthProcessSampler(),
            store: AppHealthRecordStore(),
            hangChecker: AppHealthHangChecker(),
            crashReports: AppHealthCrashReportLookup(),
            observers: AppHealthSystemObservers(),
            snapshot: { AppHealthSystemSignals.snapshot(at: $0, power: $1, thermal: $2) },
            powerSource: { AppHealthSystemSignals.powerSource() },
            thermalState: { AppHealthSystemSignals.thermalState() },
            // macOS posts no notification for per-process CPU, memory, or wake-ups, so a periodic timer is the only
            // way to observe them. 20 s keeps the cost near 0.02 % of one core; the 2 s tolerance lets the system
            // coalesce this wake-up with others instead of waking the CPU for it alone.
            waitForNextTick: {
                try await Task.sleep(for: AppHealthController.tickInterval, tolerance: .seconds(2))
            },
            crashReportDelay: { try await Task.sleep(for: AppHealthController.crashReportDelay) },
            now: { Date() },
            appVersion: {
                let info = Bundle.main.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? "?"
                let build = info?["CFBundleVersion"] as? String ?? "?"
                return "\(version) (\(build))"
            })
    }
}
