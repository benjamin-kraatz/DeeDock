import AppKit
import IOKit.ps

/// A system change App Health reacts to while collection is on.
enum AppHealthSystemEvent: Equatable {
    case willSleep, didWake
    case screensDidSleep, screensDidWake
    case sessionDidResignActive, sessionDidBecomeActive
    case launched(AppHealthAppIdentity)
    case terminated(AppHealthAppIdentity)
    case thermalStateChanged
    case powerSourceChanged
}

/// Delivers `AppHealthSystemEvent`s on the main actor between `start` and `stop`. Tests pass a fake that sends
/// events by hand.
protocol AppHealthSystemObserving: AnyObject {
    /// Installs every observer. Calling it while started replaces the handler.
    func start(_ handler: @escaping (AppHealthSystemEvent) -> Void)
    /// Removes every observer and the power-source run-loop source.
    func stop()
}

/// The live observers: `NSWorkspace` sleep, display, session, and app notifications, the thermal-state
/// notification, and an IOKit power-source run-loop source.
///
/// Everything is event-driven; nothing polls. All tokens and the run-loop source are owned here and removed in
/// `stop`, which the controller calls whenever collection stops, and in `deinit`.
final class AppHealthSystemObservers: AppHealthSystemObserving {
    private var handler: ((AppHealthSystemEvent) -> Void)?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    init() {}

    isolated deinit {
        stop()
    }

    func start(_ handler: @escaping (AppHealthSystemEvent) -> Void) {
        stop()
        self.handler = handler
        let workspace = NSWorkspace.shared.notificationCenter
        let simple: [(Notification.Name, AppHealthSystemEvent)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
        ]
        for (name, event) in simple {
            observe(workspace, name) { _ in event }
        }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { notification in
            Self.identity(notification).map(AppHealthSystemEvent.launched)
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { notification in
            Self.identity(notification).map(AppHealthSystemEvent.terminated)
        }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { _ in .thermalStateChanged }

        // IOKit calls back on the main run loop with this unretained pointer; `stop` removes the source before
        // this object can go away, so the pointer never dangles.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(appHealthPowerSourceChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        handler = nil
    }

    fileprivate func powerSourceChanged() {
        handler?(.powerSourceChanged)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         event: @escaping @MainActor (Notification) -> AppHealthSystemEvent?) {
        // Thermal-state notifications arrive on an arbitrary thread; `.main` delivers every one on the main queue.
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let event = event(notification) else { return }
                self.handler?(event)
            }
        }
        observers.append((center, token))
    }

    private static func identity(_ notification: Notification) -> AppHealthAppIdentity? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            .flatMap(AppHealthAppIdentity.init)
    }
}

/// IOKit calls this on the main run loop when the power source changes.
private nonisolated func appHealthPowerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<AppHealthSystemObservers>.fromOpaque(pointer).takeUnretainedValue().powerSourceChanged()
    }
}
