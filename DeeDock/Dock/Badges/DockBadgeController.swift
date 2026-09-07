import AppKit
import Observation

/// One cancellable badge reader for all display docks. Disabled and sleeping sessions do no AX work.
@MainActor @Observable
final class DockBadgeController {
    private(set) var labels: [String: String] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var generation = UUID()

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
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(center, name) { $0.suspended = true; $0.pause() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(center, name) { $0.suspended = false; $0.resume() }
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
        guard enabled, !suspended, worker == nil else { return }
        let reader = DockBadgeReader()
        let session = UUID()
        generation = session
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        worker = Task { [weak self] in
            for await _ in events {
                // Coalesce AX bursts and never overlap cross-process reads.
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                guard !Task.isCancelled else { break }
                let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
                let next = await reader.read(pid: pid)
                guard !Task.isCancelled, let self, generation == session else { break }
                if labels != next { labels = next }
            }
            await reader.stop()
        }
        // AXStatusLabel has no guaranteed change notification. This is a bounded fallback,
        // independent of frame rate and pointer activity, also detecting permission revocation.
        let timer = Timer(timeInterval: 5, repeats: true) { _ in continuation.yield(()) }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        continuation.yield(())
    }

    private func pause() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
        worker?.cancel()
        worker = nil
        if !labels.isEmpty { labels = [:] }
    }

    /// Releases workspace/AX observation and clears presentation state.
    func stop() {
        enabled = false
        suspended = false
        pause()
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }
}
