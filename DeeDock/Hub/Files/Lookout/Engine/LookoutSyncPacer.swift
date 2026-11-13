import Foundation

/// When a sync should follow folder changes. A pure value: `LookoutEngine` reports changes and syncs with their times
/// and owns the task that waits for `deadline`.
///
/// Three rules, so a burst of changes costs one sync and continuous churn costs a few:
/// - **Quiet period.** A sync waits until changes have stopped for `quiet` (a copy in progress, a burst of
///   screenshots).
/// - **Maximum wait.** It never waits more than `maxWait` after the first change it covers, so a folder that never
///   goes quiet (a build, a sync client) still gets its new files indexed.
/// - **Minimum gap.** While syncs keep following each other within `burstWindow`, the next one waits at least `gap`
///   after the last, and `gap` doubles each time from `minGap` up to `maxGap`. It returns to `minGap` after `resetAfter`
///   without a sync. While the Files tab is visible there is no gap: someone may be looking for the new file.
///
/// Every reported change is covered by exactly one later sync: `synced(at:)` clears the pending changes, and only
/// `changed(at:)` makes a deadline exist.
nonisolated struct LookoutSyncPacer: Sendable, Equatable {
    struct Timing: Sendable, Equatable {
        var quiet: Duration
        var maxWait: Duration
        var minGap: Duration
        var maxGap: Duration
        var burstWindow: Duration
        var resetAfter: Duration

        /// 2 s quiet, at most 30 s from the first change, gaps from 2 s to 60 s, reset after 5 quiet minutes.
        static func standard(quiet: Duration = .seconds(2)) -> Timing {
            Timing(quiet: quiet, maxWait: .seconds(30), minGap: .seconds(2), maxGap: .seconds(60),
                   burstWindow: .seconds(60), resetAfter: .seconds(300))
        }
    }

    typealias Instant = ContinuousClock.Instant

    let timing: Timing
    /// The first and the latest change not yet covered by a sync; nil when none waits.
    private(set) var firstChange: Instant?
    private(set) var lastChange: Instant?
    private(set) var lastSync: Instant?
    /// The current minimum time between two syncs, outside the Files tab.
    private(set) var gap: Duration

    init(timing: Timing) {
        self.timing = timing
        gap = timing.minGap
    }

    /// Whether changes wait for a sync.
    var isPending: Bool { firstChange != nil }

    /// A change was reported at `now`.
    mutating func changed(at now: Instant) {
        if firstChange == nil { firstChange = now }
        lastChange = now
    }

    /// When the pending changes should be synced, or nil when none wait. May be in the past: sync at once.
    func deadline(filesVisible: Bool) -> Instant? {
        guard let firstChange, let lastChange else { return nil }
        let due = min(lastChange + timing.quiet, firstChange + timing.maxWait)
        guard !filesVisible, let lastSync else { return due }
        return max(due, lastSync + gap)
    }

    /// A sync for the pending changes started at `now`. Changes reported from here on wait for the next one.
    mutating func synced(at now: Instant) {
        if let lastSync {
            let since = lastSync.duration(to: now)
            if since < timing.burstWindow {
                gap = min(gap * 2, timing.maxGap)
            } else if since >= timing.resetAfter {
                gap = timing.minGap
            }
        }
        lastSync = now
        firstChange = nil
        lastChange = nil
    }

    /// Forgets pending changes and the pace: Lookout stopped.
    mutating func reset() {
        self = LookoutSyncPacer(timing: timing)
    }
}
