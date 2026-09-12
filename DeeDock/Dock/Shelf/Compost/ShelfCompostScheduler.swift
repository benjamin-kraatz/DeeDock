import AppKit

/// Owns one aging deadline and wake/clock observers for the shared Shelf controller.
/// All callbacks run on the main run loop. `stop()` removes every registration.
@MainActor
final class ShelfCompostScheduler {
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var action: (() -> Void)?

    isolated deinit { stop() }

    func start(action: @escaping () -> Void) {
        stop()
        self.action = action
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification)
        observe(.default, name: NSApplication.didBecomeActiveNotification)
        observe(.default, name: .NSSystemClockDidChange)
    }

    func schedule(_ date: Date?) {
        timer?.invalidate()
        timer = nil
        guard let date, action != nil else { return }
        let next = Timer(fire: max(date, Date().addingTimeInterval(1)), interval: 0, repeats: false) {
            [weak self] _ in MainActor.assumeIsolated { self?.action?() }
        }
        next.tolerance = 1
        timer = next
        // Default mode lets native menus and drags settle before an automatic archive edit.
        RunLoop.main.add(next, forMode: .default)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        action = nil
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.action?() }
        }
        observers.append((center, token))
    }
}
