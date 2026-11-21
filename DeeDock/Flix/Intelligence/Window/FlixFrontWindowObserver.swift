import AppKit
import ApplicationServices
import Synchronization

/// Tells Flix Files when the window in front changes: another app comes forward, the app's focused
/// window changes, or that window's title changes (a new page, a new conversation).
///
/// No polling. NSWorkspace's activation notification reports app switches; one `AXObserver` on the
/// frontmost app at a time adds `kAXFocusedWindowChangedNotification` and
/// `kAXMainWindowChangedNotification` on the app and `kAXTitleChangedNotification` on its focused
/// window (re-registered when focus moves). Each burst is coalesced for ``settle`` before
/// ``changed`` runs, so a page that retitles itself while loading reports once.
///
/// Nothing here talks to another app on the main actor. Creating the observer, registering its
/// notifications, and reading the focused window are IPC that a busy app can hold up, so they run
/// on ``FlixAXThread`` with a messaging timeout on every element, and only after the switch has
/// settled: flicking through apps with Command-Tab costs no IPC at all. Every switch bumps a
/// generation; work queued for an earlier one is skipped on the thread, and a callback from an app
/// that is no longer in front is dropped on the main actor.
///
/// Needs Accessibility permission for the window and title notifications; without it only app
/// switches are reported. It never asks for the permission. ``stop()`` removes the workspace
/// observer and, on the thread, the notifications and the run-loop source. Main actor.
@MainActor
final class FlixFrontWindowObserver {
    /// How long a burst of notifications settles before it is reported.
    static let settle: Duration = .milliseconds(350)
    /// The longest any single Accessibility call to the observed app may take.
    nonisolated static let messagingTimeout: Float = 0.2

    /// The window in front changed. DOKK itself coming forward is not reported.
    var changed: ((NSRunningApplication) -> Void)?

    private let session = Session()
    private var workspaceObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    /// The pending report also moves the observer to the app (an app switch is settling).
    private var pendingAttach = false
    /// The app the observer follows, for dropping callbacks from an earlier one.
    private var current: pid_t = 0
    private(set) var isRunning = false

    init() {
        session.received = { [weak self] pid in self?.received(pid: pid) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        activated(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        pending?.cancel()
        pending = nil
        pendingAttach = false
        current = 0
        let generation = session.advance()
        let session = session
        FlixAXThread.shared.perform { session.detach(generation: generation) }
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        current = app.processIdentifier
        // Any attach queued for the previous app is now stale.
        session.advance()
        schedule(app, attach: true)
    }

    /// Coalesces notifications: only the last one in ``settle`` is reported. After an app switch,
    /// the observer moves to the new app only once the switch has settled.
    private func schedule(_ app: NSRunningApplication, attach: Bool) {
        pending?.cancel()
        // A notification arriving while a switch settles keeps that switch's attach.
        let attach = attach || pendingAttach
        pendingAttach = attach
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard let self, !Task.isCancelled, isRunning, !app.isTerminated,
                  app.processIdentifier == current else { return }
            pendingAttach = false
            if attach {
                let generation = session.generation
                let session = session
                let pid = app.processIdentifier
                FlixAXThread.shared.perform { session.attach(to: pid, generation: generation) }
            }
            changed?(app)
        }
    }

    /// A notification from the observed app, already moved to the main actor.
    private func received(pid: pid_t) {
        guard isRunning, pid == current, let app = NSRunningApplication(processIdentifier: pid) else { return }
        // The thread already moved the title notification for a focus change.
        schedule(app, attach: false)
    }

    // MARK: On the Accessibility thread

    /// The observer's Accessibility state. Confined to ``FlixAXThread``: every method except
    /// ``advance()`` and ``generation`` runs there. The generation is shared through a mutex.
    nonisolated final class Session: @unchecked Sendable {
        private let latest = Mutex(0)
        /// Set once at init on the main actor, read on the thread.
        /// Called on the main actor with the observed app's process.
        var received: (@MainActor @Sendable (pid_t) -> Void)?

        private var observer: AXObserver?
        private var observedApp: AXUIElement?
        private var observedWindow: AXUIElement?
        private var observedPID: pid_t = 0

        var generation: Int { latest.withLock { $0 } }

        /// Starts a new generation; work queued for an older one is skipped.
        @discardableResult
        func advance() -> Int { latest.withLock { $0 += 1; return $0 } }

        private func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

        func attach(to pid: pid_t, generation: Int) {
            guard isCurrent(generation), pid != observedPID else { return }
            removeObserver()
            guard AXIsProcessTrusted(), isCurrent(generation) else { return }
            var created: AXObserver?
            guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, FlixFrontWindowObserver.messagingTimeout)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(created, element, kAXFocusedWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(created, element, kAXMainWindowChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
            observer = created
            observedApp = element
            observedPID = pid
            // Another switch while registering: let the next attach replace this one.
            guard isCurrent(generation) else { return }
            observeFocusedWindow()
        }

        func detach(generation: Int) {
            guard isCurrent(generation) else { return }
            removeObserver()
        }

        private func removeObserver() {
            if let observer {
                if let observedWindow {
                    AXObserverRemoveNotification(observer, observedWindow, kAXTitleChangedNotification as CFString)
                }
                if let observedApp {
                    AXObserverRemoveNotification(observer, observedApp, kAXFocusedWindowChangedNotification as CFString)
                    AXObserverRemoveNotification(observer, observedApp, kAXMainWindowChangedNotification as CFString)
                }
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            observer = nil
            observedApp = nil
            observedWindow = nil
            observedPID = 0
        }

        /// Moves the title notification to the window that has focus now.
        private func observeFocusedWindow() {
            guard let observer, let observedApp else { return }
            if let observedWindow {
                AXObserverRemoveNotification(observer, observedWindow, kAXTitleChangedNotification as CFString)
            }
            observedWindow = RobiAX.element(observedApp, kAXFocusedWindowAttribute)
            if let observedWindow {
                AXUIElementSetMessagingTimeout(observedWindow, FlixFrontWindowObserver.messagingTimeout)
                AXObserverAddNotification(observer, observedWindow, kAXTitleChangedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            }
        }

        fileprivate func notified(_ notification: String) {
            guard observer != nil else { return }
            if notification != kAXTitleChangedNotification as String { observeFocusedWindow() }
            let received = received
            let pid = observedPID
            Task { @MainActor in received?(pid) }
        }

        /// The AX callback runs on ``FlixAXThread``'s run loop, where the source was added.
        /// `refcon` is this session, unretained: the observer owns it for its whole life, and the
        /// source is removed on this thread (``detach(generation:)``) before the session could go
        /// away, so no callback can outlive it.
        private static let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let session = Unmanaged<Session>.fromOpaque(refcon).takeUnretainedValue()
            session.notified(notification as String)
        }
    }
}
