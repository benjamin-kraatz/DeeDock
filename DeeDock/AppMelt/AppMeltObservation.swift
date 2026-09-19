import AppKit
import ApplicationServices

/// AX sources are installed only on the main run loop and removed before releasing the callback
/// context. Notifications are hints: the service revalidates exact source identity before acting.
@MainActor final class AppMeltObservation {
    private var observers: [AXObserver] = []
    private var processes: Set<pid_t> = []
    var changed: (() -> Void)?

    func start(processes requestedProcesses: [pid_t], forceRestart: Bool = false) -> Bool {
        let requested = Set(requestedProcesses)
        guard !requested.isEmpty else { stop(); return false }
        if !forceRestart, requested == processes, observers.count == requested.count { return true }
        stop()
        for pid in requested {
            var observer: AXObserver?
            let status = AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<AppMeltObservation>.fromOpaque(context).takeUnretainedValue().changed?()
                }
            }, &observer)
            guard status == .success, let observer else { stop(); return false }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { stop(); return false }
            let context = Unmanaged.passUnretained(self).toOpaque()
            var supported = Set<String>()
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.15)
                for event in [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
                              kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] {
                    if AXObserverAddNotification(observer, window, event as CFString, context) == .success { supported.insert(event) }
                }
            }
            guard [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification]
                .allSatisfy({ supported.contains($0) }) else { stop(); return false }
            for event in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
                _ = AXObserverAddNotification(observer, app, event as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.append(observer)
        }
        processes = requested
        return true
    }

    func stop() {
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        processes.removeAll()
    }
}
