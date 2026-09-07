import AppKit
import Observation

/// One cancellable badge reader for all display docks. Disabled and sleeping sessions do no AX work.
@MainActor @Observable
final class DockBadgeController {
    let memory = BadgeMemoryStore()
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
                let next = await reader.read(pid: pid)
                guard !Task.isCancelled, let self, generation == session else { break }
                memory.observe(next, session: focusSession?())
                let nextLabels = next.compactMapValues(\.label)
                if labels != nextLabels { labels = nextLabels }
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

    private func pause() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
        worker?.cancel()
        if !labels.isEmpty { labels = [:] }
        memory.observe([:], session: focusSession?())
    }

    /// Releases workspace/AX observation and clears presentation state.
    func stop() {
        enabled = false
        suspensionReasons = []
        pause()
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }
}
