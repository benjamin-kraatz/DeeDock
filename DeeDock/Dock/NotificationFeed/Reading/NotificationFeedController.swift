import AppKit
import ApplicationServices
import Observation

/// Owns the notification reader for every dock: when it runs, what it collects, and its teardown.
///
/// Reading happens only while the feature is enabled, Accessibility is trusted, NotificationCenter
/// is running, and the Mac is awake with this login session active. Each Accessibility change
/// signal starts one coalesced pass; passes never overlap. Disabling the feature removes every
/// observer and forgets every collected entry.
@MainActor @Observable
final class NotificationFeedController {
    /// What the feed can do right now, shown in its popover and Settings.
    enum State: Equatable {
        /// The feature is off. Nothing is observed.
        case off
        /// The feature is on, but DOKK has no Accessibility access yet.
        case needsAccess
        /// Access is granted, but the NotificationCenter process is not running or not answering.
        case waiting
        /// Banners are being collected.
        case listening
    }

    let store: NotificationFeedStore
    private(set) var state: State = .off
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerSession: UUID?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var continuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Runs only while the feature is on and access is missing, to notice the grant without a relaunch.
    @ObservationIgnored private var accessTimer: Timer?
    @ObservationIgnored private let isTrusted: () -> Bool
    @ObservationIgnored private let notificationCenterPID: () -> pid_t?
    /// A one-shot follow-up pass, for unfilled banners and for recovery after a failed pass.
    @ObservationIgnored private var followUp: Timer?
    @ObservationIgnored private var retryDelay: TimeInterval = 0
    @ObservationIgnored private var settlingPasses = 0
    private enum SuspensionReason { case systemSleep, screenSleep, inactiveSession }
    @ObservationIgnored private var suspensionReasons: Set<SuspensionReason> = []

    /// Bursts of layout changes, two to four per banner, become one pass. A banner holds for five
    /// seconds, so this delay is far inside its lifetime.
    private static let coalescing: Duration = .milliseconds(100)
    /// How long to wait before re-reading a banner macOS had not filled in yet.
    private static let settlingDelay: TimeInterval = 0.3
    private static let maximumSettlingPasses = 3

    /// True while the feature waits for an Accessibility grant and re-checks it on a timer.
    var isCheckingAccess: Bool { accessTimer != nil }

    /// - Parameters:
    ///   - store: `nil` creates an empty store. It is created in this body because a default
    ///     argument is type-checked outside the main actor.
    ///   - isTrusted: Whether DOKK has Accessibility access. Tests replace the system check.
    ///   - notificationCenterPID: The running NotificationCenter process, if any.
    init(store: NotificationFeedStore? = nil,
         isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         notificationCenterPID: @escaping () -> pid_t? = {
             NSRunningApplication.runningApplications(
                 withBundleIdentifier: NotificationFeedReader.bundleIdentifier).first?.processIdentifier
         }) {
        self.store = store ?? NotificationFeedStore()
        self.isTrusted = isTrusted
        self.notificationCenterPID = notificationCenterPID
    }

    /// Starts or stops collecting. Called on every settings change; repeated values do nothing.
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            installObservers()
            resume()
        } else {
            stop()
        }
    }

    /// Re-checks Accessibility after the person may have changed it, such as on returning from System Settings.
    func refreshAccess() {
        guard enabled, suspensionReasons.isEmpty else { return }
        let trusted = isTrusted()
        if trusted, state == .needsAccess { resume() }
        else if !trusted, state != .needsAccess { restart() }
    }

    private func installObservers() {
        observe(.default, NotificationFeedReader.changedNotification) { $0.signal() }
        observe(.default, NSApplication.didBecomeActiveNotification) { $0.refreshAccess() }
        let workspace = NSWorkspace.shared.notificationCenter
        // NotificationCenter relaunching gets a new process. Reattach to it instead of polling.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(workspace, name) { controller, notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard application?.bundleIdentifier == NotificationFeedReader.bundleIdentifier else { return }
                controller.restart()
            }
        }
        observeSuspension(workspace, sleep: NSWorkspace.willSleepNotification,
                          wake: NSWorkspace.didWakeNotification, reason: .systemSleep)
        observeSuspension(workspace, sleep: NSWorkspace.screensDidSleepNotification,
                          wake: NSWorkspace.screensDidWakeNotification, reason: .screenSleep)
        observeSuspension(workspace, sleep: NSWorkspace.sessionDidResignActiveNotification,
                          wake: NSWorkspace.sessionDidBecomeActiveNotification, reason: .inactiveSession)
    }

    private func observeSuspension(_ center: NotificationCenter, sleep: Notification.Name,
                                   wake: Notification.Name, reason: SuspensionReason) {
        observe(center, sleep) { controller, _ in
            controller.suspensionReasons.insert(reason)
            controller.pause()
        }
        observe(center, wake) { controller, _ in
            // A display waking must not restart reading for an inactive login session.
            controller.suspensionReasons.remove(reason)
            controller.resume()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (NotificationFeedController) -> Void) {
        observe(center, name) { controller, _ in action(controller) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (NotificationFeedController, Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { if let self { action(self, notification) } }
        }
        observers.append((center, token))
    }

    private func signal() { continuation?.yield(()) }

    private func restart() {
        pause()
        resume()
    }

    private func resume() {
        guard enabled, suspensionReasons.isEmpty, worker == nil else { return }
        guard isTrusted() else {
            state = .needsAccess
            startAccessTimer()
            return
        }
        stopAccessTimer()
        guard let pid = notificationCenterPID() else {
            // The workspace launch notification resumes reading once the process exists.
            state = .waiting
            return
        }
        let reader = NotificationFeedReader()
        let session = UUID()
        generation = session
        workerSession = session
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        worker = Task { [weak self] in
            for await _ in events {
                do { try await Task.sleep(for: Self.coalescing) } catch { break }
                guard !Task.isCancelled else { break }
                let pass = await reader.read(pid: pid)
                guard !Task.isCancelled, let self, generation == session else { break }
                apply(pass)
            }
            await reader.stop()
            self?.workerFinished(session)
        }
        // The first pass registers the observer and collects banners already on screen.
        continuation.yield(())
    }

    private func apply(_ pass: NotificationFeedPass?) {
        guard let pass else {
            guard isTrusted() else { restart(); return }
            state = .waiting
            scheduleRetry()
            return
        }
        store.ingest(pass.readings, at: .now)
        guard pass.observing else {
            state = .waiting
            scheduleRetry()
            return
        }
        state = .listening
        retryDelay = 0
        // macOS can expose a banner before its texts. Read it again shortly, a few times at most.
        if pass.readings.contains(where: { !$0.isPopulated }), settlingPasses < Self.maximumSettlingPasses {
            settlingPasses += 1
            scheduleFollowUp(after: Self.settlingDelay)
        } else {
            settlingPasses = 0
        }
    }

    /// Backs off from two seconds to thirty while NotificationCenter fails to answer or to accept
    /// the observer. Without a registered observer no change signal would ever arrive.
    private func scheduleRetry() {
        retryDelay = min(max(retryDelay * 2, 2), 30)
        scheduleFollowUp(after: retryDelay)
    }

    private func scheduleFollowUp(after delay: TimeInterval) {
        followUp?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followUp = nil
                self?.signal()
            }
        }
        timer.tolerance = delay * 0.1
        RunLoop.main.add(timer, forMode: .common)
        followUp = timer
    }

    private func startAccessTimer() {
        guard accessTimer == nil else { return }
        // No public notification reports a changed Accessibility grant. This check is a local
        // call, and it runs only until access is granted or the feature is turned off.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccess() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    private func stopAccessTimer() {
        accessTimer?.invalidate()
        accessTimer = nil
    }

    private func workerFinished(_ session: UUID) {
        guard workerSession == session else { return }
        worker = nil
        workerSession = nil
        // Cancellation cannot interrupt a synchronous AX call already in flight. A replacement
        // starts only after that call returns and the old observer has been released.
        resume()
    }

    /// Stops reading but keeps the collected entries, for sleep, a locked session, or a reattach.
    private func pause() {
        generation = UUID()
        followUp?.invalidate()
        followUp = nil
        stopAccessTimer()
        continuation?.finish()
        continuation = nil
        worker?.cancel()
        retryDelay = 0
        settlingPasses = 0
        if enabled, state == .listening { state = .waiting }
    }

    /// Releases every observer and forgets the collected notifications.
    func stop() {
        enabled = false
        suspensionReasons = []
        pause()
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        store.reset()
        state = .off
    }
}
