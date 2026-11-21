import AppKit
import ApplicationServices

/// Tells Flix Files when the window in front changes: another app comes forward, the app's focused
/// window changes, or that window's title changes (a new page, a new conversation).
///
/// No polling. One `AXObserver` on the frontmost app at a time, registered for
/// `kAXFocusedWindowChangedNotification` and `kAXMainWindowChangedNotification` on the app and
/// `kAXTitleChangedNotification` on its focused window (re-registered when focus moves), plus
/// NSWorkspace's activation notification for app switches. Each burst is coalesced for
/// ``settle`` before ``changed`` runs, so a page that retitles itself while loading reports once.
///
/// Needs Accessibility permission for the window and title notifications; without it only app
/// switches are reported. It never asks for the permission. Its run-loop source is on the main run
/// loop, and ``stop()`` removes it, the notifications, and the workspace observer. Main actor.
@MainActor
final class FlixFrontWindowObserver {
    /// How long a burst of notifications settles before it is reported.
    static let settle: Duration = .milliseconds(350)

    /// The window in front changed. DOKK itself coming forward is not reported.
    var changed: ((NSRunningApplication) -> Void)?

    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private var observedPID: pid_t = 0
    private var workspaceObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private(set) var isRunning = false

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
        detach()
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        attach(to: app)
        schedule(app)
    }

    /// Coalesces notifications: only the last one in ``settle`` is reported.
    private func schedule(_ app: NSRunningApplication) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard let self, !Task.isCancelled, isRunning, !app.isTerminated else { return }
            changed?(app)
        }
    }

    // MARK: Accessibility

    private func attach(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        detach()
        guard AXIsProcessTrusted() else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.2)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(created, element, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedApp = element
        observedPID = pid
        observeFocusedWindow()
    }

    private func detach() {
        if let observer {
            if let observedWindow {
                AXObserverRemoveNotification(observer, observedWindow, kAXTitleChangedNotification as CFString)
            }
            if let observedApp {
                AXObserverRemoveNotification(observer, observedApp, kAXFocusedWindowChangedNotification as CFString)
                AXObserverRemoveNotification(observer, observedApp, kAXMainWindowChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
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
            AXObserverAddNotification(observer, observedWindow, kAXTitleChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
    }

    fileprivate func received(_ notification: String) {
        guard isRunning, let app = NSRunningApplication(processIdentifier: observedPID) else { return }
        if notification != kAXTitleChangedNotification as String { observeFocusedWindow() }
        schedule(app)
    }

    /// The AX callback runs on the main run loop, where the source was added. `refcon` is this
    /// object, unretained: `FlixContextServices` owns the observer for the app's lifetime and calls
    /// ``stop()``, which removes the source, before it could go away.
    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let observer = Unmanaged<FlixFrontWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        MainActor.assumeIsolated { observer.received(name) }
    }
}
