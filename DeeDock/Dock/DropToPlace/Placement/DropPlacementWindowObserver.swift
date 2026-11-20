import ApplicationServices
import Foundation

/// Wakes a waiting placement when an app creates or focuses a window.
///
/// Ownership: one observer belongs to one placement task, which calls ``stop()`` when it ends,
/// whether it placed, timed out, or was cancelled.
///
/// AX registration and removal message the app synchronously. A freshly launched app is often
/// too busy to answer and can hold each message for the full messaging timeout, so both run on
/// a private serial queue, never on the main actor. Only callback delivery uses the main run
/// loop. The callback context is a ``Relay`` retained by the registration; it holds the observer
/// weakly, so the observer can go away while a registration is still being made or removed.
///
/// AX notifications only wake the waiter. The waiter still asks `DropPlacementAccessibility` for
/// a window, so a window that already existed, or one an app restored without posting
/// `kAXWindowCreatedNotification`, is found as well.
@MainActor
final class DropPlacementWindowObserver {
    private var registration: Registration?
    private var processIdentifier: pid_t?
    /// True while a registration for ``processIdentifier`` is being made off the main actor.
    private var registering = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var pending = false

    /// Starts observing `processIdentifier`. Safe to call repeatedly: an app that has just
    /// launched may refuse registration until it is ready, so each call retries until one
    /// succeeds. Returns at once; registration finishes in the background.
    func observe(_ processIdentifier: pid_t) {
        if self.processIdentifier == processIdentifier, registration != nil || registering { return }
        removeRegistration()
        self.processIdentifier = processIdentifier
        registering = true
        let relay = Relay(owner: self)
        Registration.queue.async { [weak self] in
            let made = Registration.make(processIdentifier: processIdentifier, relay: relay)
            Task { @MainActor [weak self] in
                guard let self, self.processIdentifier == processIdentifier, self.registering else {
                    made?.remove()
                    return
                }
                registering = false
                registration = made
            }
        }
    }

    /// Returns after the next notification, or after `timeout`, whichever is first.
    /// A notification that arrived since the last wait returns at once.
    func next(timeout: Duration) async {
        if pending { pending = false; return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.signal()
        }
        defer { timer.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || pending { pending = false; continuation.resume(); return }
                waiter = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.signal() }
        }
        pending = false
    }

    /// Removes every registration and resumes a waiter. Call when the placement ends.
    func stop() {
        removeRegistration()
        processIdentifier = nil
        signal()
        pending = false
    }

    fileprivate func signal() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            pending = true
        }
    }

    private func removeRegistration() {
        // A registration still in flight sees `registering == false` and removes itself.
        registering = false
        registration?.remove()
        registration = nil
    }
}

/// The AX callback's context. Retained by its ``Registration`` until removal finishes.
private nonisolated final class Relay: @unchecked Sendable {
    /// Read only on the main actor, where the callback is delivered.
    weak var owner: DropPlacementWindowObserver?

    init(owner: DropPlacementWindowObserver) { self.owner = owner }
}

/// One AXObserver with its notifications and main-run-loop source. Made and removed on ``queue``.
private nonisolated final class Registration: @unchecked Sendable {
    static let queue = DispatchQueue(label: "DeeDock.DropPlacement.observer")
    private static let notifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                        kAXMainWindowChangedNotification]
    /// Bounds each registration message to a busy app. Off the main actor, so only this queue waits.
    private static let messagingTimeout: Float = 0.25

    private let observer: AXObserver
    private let application: AXUIElement
    private let context: Unmanaged<Relay>

    private init(observer: AXObserver, application: AXUIElement, context: Unmanaged<Relay>) {
        self.observer = observer
        self.application = application
        self.context = context
    }

    /// Creates the observer and registers it. Runs on ``queue``. Nil when the app refuses every
    /// notification, for example because it has not finished launching.
    static func make(processIdentifier: pid_t, relay: Relay) -> Registration? {
        var created: AXObserver?
        let status = AXObserverCreate(processIdentifier, { _, _, _, context in
            guard let context else { return }
            // Delivered on the main run loop, where the source is installed.
            MainActor.assumeIsolated {
                Unmanaged<Relay>.fromOpaque(context).takeUnretainedValue().owner?.signal()
            }
        }, &created)
        guard status == .success, let created else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let context = Unmanaged.passRetained(relay)
        var registered = false
        for name in notifications
        where AXObserverAddNotification(created, application, name as CFString, context.toOpaque()) == .success {
            registered = true
        }
        guard registered else {
            context.release()
            return nil
        }
        // CFRunLoopAddSource is thread-safe; delivery happens on the main run loop.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        return Registration(observer: created, application: application, context: context)
    }

    /// Unregisters on ``queue``. The context is released on the main queue afterwards: the
    /// source is already gone from the main run loop by then, so no callback can still use it.
    func remove() {
        Self.queue.async { [self] in
            for name in Self.notifications {
                AXObserverRemoveNotification(observer, application, name as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            let context = context
            DispatchQueue.main.async { context.release() }
        }
    }
}
