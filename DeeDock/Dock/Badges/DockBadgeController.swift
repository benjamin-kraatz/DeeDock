import AppKit
import Observation

/// One cancellable badge reader for all display docks. Disabled and sleeping sessions do no AX work.
@MainActor @Observable
final class DockBadgeController {
    let memory: BadgeMemoryStore
    /// Which of the presented badges are news. Line icon docks draw those as a red ring.
    let attention: BadgeAttentionStore
    @ObservationIgnored var focusSession: (() -> FocusSession?)?
    private(set) var labels: [String: String] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var enabled = false
    private enum SuspensionReason { case systemSleep, screenSleep, inactiveSession }
    @ObservationIgnored private var suspensionReasons: Set<SuspensionReason> = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var workerSession: UUID?
    @ObservationIgnored private var retention = BadgeScanRetention()
    /// Badges that were news after the last real scan, for counting arrivals. Nil until the first
    /// scan after enabling, which only seeds it, so standing badges are not counted at each launch.
    /// Pausing keeps it, so waking does not count them either.
    @ObservationIgnored private var newKeys: Set<String>?

    /// `nil` uses standard defaults. The store is created in this body because a default
    /// argument is type-checked outside the main actor.
    init(memory: BadgeMemoryStore? = nil, attention: BadgeAttentionStore? = nil) {
        self.memory = memory ?? BadgeMemoryStore()
        self.attention = attention ?? BadgeAttentionStore()
    }

    /// Starts observation only for an enabled feature with at least one configured Dock.
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { installObservers(); resume() } else { stop() }
    }

    private func installObservers() {
        observe(.default, NSNotification.Name("DDockBadgeAXChanged")) { $0.continuation?.yield(()) }
        observe(.default, NSApplication.didBecomeActiveNotification) { $0.continuation?.yield(()) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(center, name) { $0.continuation?.yield(()) }
        }
        // Bringing an app to the front, by any route, counts as looking at its badge.
        observe(center, NSWorkspace.didActivateApplicationNotification) { controller in
            guard let key = Self.frontmostKey() else { return }
            controller.attention.acknowledge(key: key, label: controller.labels[key], via: .activation)
        }
        observeSuspension(center, sleep: NSWorkspace.willSleepNotification,
                          wake: NSWorkspace.didWakeNotification, reason: .systemSleep)
        observeSuspension(center, sleep: NSWorkspace.screensDidSleepNotification,
                          wake: NSWorkspace.screensDidWakeNotification, reason: .screenSleep)
        observeSuspension(center, sleep: NSWorkspace.sessionDidResignActiveNotification,
                          wake: NSWorkspace.sessionDidBecomeActiveNotification, reason: .inactiveSession)
    }

    private func observeSuspension(_ center: NotificationCenter, sleep: Notification.Name,
                                   wake: Notification.Name, reason: SuspensionReason) {
        observe(center, sleep) {
            $0.suspensionReasons.insert(reason)
            $0.pause()
        }
        observe(center, wake) {
            // A display waking must not restart work for an inactive user session.
            $0.suspensionReasons.remove(reason)
            $0.resume()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (DockBadgeController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    private func resume() {
        guard enabled, suspensionReasons.isEmpty, worker == nil else { return }
        let reader = DockBadgeReader()
        let session = UUID()
        generation = session
        workerSession = session
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        worker = Task { [weak self] in
            for await _ in events {
                // Coalesce AX bursts and never overlap cross-process reads.
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                guard !Task.isCancelled else { break }
                self?.timer?.invalidate()
                self?.timer = nil
                let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
                let scanStarted = Date()
                let next = await reader.read(pid: pid)
                guard !Task.isCancelled, let self, generation == session else { break }
                // One AX timeout must not blank every dot or write unknown values into history.
                self.applyScan(next, at: .now, scanStarted: scanStarted)
                scheduleFallback()
            }
            await reader.stop()
            self?.workerFinished(session)
        }
        continuation.yield(())
    }

    private func workerFinished(_ session: UUID) {
        guard workerSession == session else { return }
        worker = nil
        workerSession = nil
        // Cancellation cannot interrupt an in-flight synchronous AX call. A replacement
        // starts only after that call returns and its observer has been released.
        resume()
    }

    private func scheduleFallback() {
        timer?.invalidate()
        // Schedule after completion, so a slow scan does not accumulate periodic refreshes.
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.continuation?.yield(()) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the reader and hides badges until the next scan result.
    ///
    /// Sleep, display sleep, session resign, and shutdown all come through here. Hiding the
    /// badges is not an observation: history does not gain `.unknown`, and the grace clock
    /// keeps running from the last successful scan. A failure inside that grace shows the
    /// hidden snapshot again.
    func pause() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
        worker?.cancel()
        retention.suspend(keeping: memory.current)
        memory.markGap(session: focusSession?())
        if !labels.isEmpty { labels = [:] }
        memory.present([:])
    }

    /// Applies one reader result. `snapshot` is nil when the scan threw.
    func applyScan(_ snapshot: [String: BadgeObservation]?, at now: ContinuousClock.Instant, scanStarted: Date) {
        switch retention.resolve(snapshot, at: now) {
        case .retain(let hidden):
            memory.markGap(session: focusSession?(), scanStarted: scanStarted)
            if let hidden {
                memory.present(hidden)
                publish(hidden)
            }
        case .update(let snapshot):
            memory.observe(snapshot, session: focusSession?(), scanStarted: scanStarted)
            // Only a real scan may forget acknowledgements; a retained snapshot is not an observation.
            attention.reconcile(snapshot, frontmost: Self.frontmostKey())
            publish(snapshot)
            countAttention()
        }
    }

    /// Counts badges that became news, and news the app took away before anyone acknowledged it.
    private func countAttention() {
        let current = Set(labels.filter { attention.isNew(key: $0.key, label: $0.value) }.keys)
        defer { newKeys = current }
        guard let previous = newKeys else { return }
        for _ in current.subtracting(previous) { Analytics.count(.badgeNew) }
        for key in previous.subtracting(current) where labels[key] == nil {
            Analytics.count(.badgeClearedWhileNew)
        }
    }

    /// The badge key of the frontmost application.
    private static func frontmostKey() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleURL.map(DockBadgePath.key(for:))
    }

    private func publish(_ snapshot: [String: BadgeObservation]) {
        let nextLabels = snapshot.compactMapValues(\.label)
        if labels != nextLabels { labels = nextLabels }
    }

    /// Releases workspace/AX observation and clears presentation state.
    func stop() {
        enabled = false
        newKeys = nil
        suspensionReasons = []
        pause()
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }
}
