import Foundation

/// What the in-memory history says about an app's last minutes before it terminated. Pure.
///
/// The derived meanings are documented in `docs/APP-HEALTH.md`, not stored: a crash report means an unexpected
/// termination; no report but `heavyBefore` reads as "quit shortly after heavy use"; `hangFailing` without a report
/// suggests a force quit of a frozen app. A Force Quit (SIGKILL) and a normal quit look the same through public API.
nonisolated enum AppHealthTerminationSignals {
    /// How far back `heavyBefore` and `frontmostRecently` look.
    static let window: TimeInterval = 120
    /// Mean CPU percentage over the window that counts as heavy.
    static let heavyPercent = 50.0

    struct Result: Sendable, Equatable {
        let heavyBefore: Bool
        let hangFailing: Bool
        let frontmostRecently: Bool
    }

    /// - Parameter history: The app's samples, oldest first.
    static func evaluate(_ history: [AppHealthSample], terminatedAt: Date) -> Result {
        let recent = history.filter {
            $0.timestamp <= terminatedAt && terminatedAt.timeIntervalSince($0.timestamp) <= window
        }
        let meanCPU = recent.isEmpty ? 0 : recent.map(\.cpuPercent).reduce(0, +) / Double(recent.count)
        let lastCheck = history.last { $0.hang != nil }?.hang
        return Result(heavyBefore: !recent.isEmpty && meanCPU >= heavyPercent,
                      hangFailing: lastCheck == .timeout,
                      frontmostRecently: recent.contains(where: \.frontmost))
    }
}
