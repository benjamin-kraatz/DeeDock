import Foundation

/// Sends ``AnalyticsEvent/lineIconCoverage(_:)`` once per launch, at most every six hours.
///
/// The app delegate owns it from launch to termination. The scan reads the Applications folders
/// the way the Launcher does, so it waits for launch to settle and runs off the main actor.
/// Nothing is scanned while analytics is off or when the last report is recent.
@MainActor
final class LineIconCoverageReporter {
    /// The shortest gap between two reports.
    static let interval: TimeInterval = 6 * 60 * 60
    private static let lastReportKey = "analytics.line-icon-coverage.last-report.v1"
    /// Keeps the folder scan out of the launch path.
    private static let launchDelay: Duration = .seconds(30)

    private let defaults: UserDefaults
    private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Schedules this launch's report. `pinned` is read when the scan begins, after the delay.
    func start(pinned: @escaping @MainActor () -> [ApplicationReference]) {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            guard !Task.isCancelled else { return }
            await self?.reportIfDue(pinned: pinned())
        }
    }

    /// Cancels a report that has not been sent yet. Call from termination.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Whether a report is due at `now`, given when the last one was sent.
    nonisolated static func isDue(lastReport: Date?, now: Date) -> Bool {
        guard let lastReport else { return true }
        // A clock set backwards would otherwise hold back every report until it caught up.
        return now < lastReport || now.timeIntervalSince(lastReport) >= interval
    }

    private func reportIfDue(pinned: [ApplicationReference]) async {
        guard Analytics.shared.acceptsEvents,
              Self.isDue(lastReport: defaults.object(forKey: Self.lastReportKey) as? Date, now: .now),
              let coverage = try? await Self.measure(pinned: pinned),
              !Task.isCancelled else { return }
        Analytics.track(.lineIconCoverage(coverage))
        defaults.set(Date.now, forKey: Self.lastReportKey)
    }

    @concurrent private nonisolated static func measure(pinned: [ApplicationReference]) async throws -> LineIconCoverage {
        // Pinned apps outside the Applications folders still count as installed, as in the Launcher.
        let snapshot = try await LauncherDiscovery.scan(extraURLs: pinned.map(\.url))
        // The Launcher hides nested copies, such as build templates inside a Unity install.
        let installed = snapshot.applications.filter { !$0.isNested }.map(\.reference)
        let catalog = LineIconCatalog.shared
        return LineIconCoverage(installed: installed, pinned: pinned,
                                hasGlyph: { catalog.hasGlyph(bundleIdentifier: $0.bundleIdentifier, url: $0.url) },
                                publicApps: .bundled())
    }
}
