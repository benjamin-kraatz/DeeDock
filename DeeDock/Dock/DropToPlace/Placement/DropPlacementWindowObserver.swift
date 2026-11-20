import ApplicationServices
import Foundation

/// Wakes a waiting placement when an app creates or focuses a window.
///
/// Ownership: one observer belongs to one placement task, which calls ``stop()`` when it ends,
/// whether it placed, timed out, or was cancelled. `stop` removes the notifications and the run
/// loop source before the observer is released, because the AX callback holds an unretained
/// pointer to this object.
///
/// AX notifications only wake the waiter. The waiter still asks `DropPlacementAccessibility` for
/// a window, so a window that already existed, or one an app restored without posting
/// `kAXWindowCreatedNotification`, is found as well.
@MainActor
final class DropPlacementWindowObserver {
    private static let notifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                        kAXMainWindowChangedNotification]
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var processIdentifier: pid_t?
    private var waiter: CheckedContinuation<Void, Never>?
    private var pending = false

    /// Starts observing `processIdentifier`. Safe to call repeatedly: an app that has just
    /// launched may refuse registration until it is ready, so each call retries until one succeeds.
    func observe(_ processIdentifier: pid_t) {
        guard self.processIdentifier != processIdentifier || observer == nil else { return }
        removeRegistration()
        var created: AXObserver?
        let status = AXObserverCreate(processIdentifier, { _, _, _, context in
            guard let context else { return }
            // Delivered on the main run loop, where the source was installed.
            MainActor.assumeIsolated {
                Unmanaged<DropPlacementWindowObserver>.fromOpaque(context).takeUnretainedValue().signal()
            }
        }, &created)
        guard status == .success, let created else { return }
        let element = AXUIElementCreateApplication(processIdentifier)
        // Registration and removal message the app synchronously on the main actor. Bound them,
        // so an app that is still busy launching cannot stall the dock.
        AXUIElementSetMessagingTimeout(element, 0.25)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var registered = false
        for name in Self.notifications where AXObserverAddNotification(created, element, name as CFString, context) == .success {
            registered = true
        }
        guard registered else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        application = element
        self.processIdentifier = processIdentifier
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

    /// Removes every registration and resumes a waiter. Required before release.
    func stop() {
        removeRegistration()
        processIdentifier = nil
        signal()
        pending = false
    }

    private func signal() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            pending = true
        }
    }

    private func removeRegistration() {
        guard let observer else { return }
        if let application {
            for name in Self.notifications { AXObserverRemoveNotification(observer, application, name as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        application = nil
    }
}
