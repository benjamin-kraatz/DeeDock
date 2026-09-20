import AppKit
import ApplicationServices

/// Observes only the active application's focused window. AX and Quartz frames use top-left points.
@MainActor
final class AtmosphereFocusedWindowTracker {
    struct Target: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
    }

    var changed: (() -> Void)?
    private var pid: pid_t?
    private var observer: AXObserver?
    private var window: AXUIElement?
    private var notificationPending = false
    private var notificationGeneration = 0

    func target() -> Target? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
            stop()
            return nil
        }
        if pid != app.processIdentifier {
            stop()
            var created: AXObserver?
            if AXObserverCreate(app.processIdentifier, { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<AtmosphereFocusedWindowTracker>.fromOpaque(context).takeUnretainedValue().scheduleChange()
                }
            }, &created) == .success, let created {
                // Assign pid only after a successful create so a failed attempt can retry
                // while this app is still frontmost. Setting it first skipped that retry.
                pid = app.processIdentifier
                observer = created
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXObserverAddNotification(created, element, kAXFocusedWindowChangedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            }
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let focused = value(application, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            observe(nil)
            return nil
        }
        let focusedWindow = focused as! AXUIElement
        observe(focusedWindow)
        guard (value(focusedWindow, kAXMinimizedAttribute) as? Bool) != true,
              let position = value(focusedWindow, kAXPositionAttribute),
              let sizeValue = value(focusedWindow, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return nil }
        let frame = CGRect(origin: origin, size: size)
        let title = value(focusedWindow, kAXTitleAttribute) as? String
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let other = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(frame.minX - other.minX) < 2 && abs(frame.minY - other.minY) < 2
                && abs(frame.width - other.width) < 2 && abs(frame.height - other.height) < 2
        }
        // Public AX does not expose a window ID. Refuse ambiguous matches rather than sample another window.
        let named = candidates.filter { title != nil && ($0[kCGWindowName as String] as? String) == title }
        let matches = named.count == 1 ? named : candidates
        guard matches.count == 1, let id = matches[0][kCGWindowNumber as String] as? UInt32 else { return nil }
        return Target(id: id, pid: app.processIdentifier, frame: frame)
    }

    /// Coalesce bursts of move/resize notifications and avoid querying AX from inside its callback.
    private func scheduleChange() {
        guard !notificationPending else { return }
        notificationPending = true
        let generation = notificationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.notificationGeneration else { return }
            self.notificationPending = false
            self.changed?()
        }
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private func observe(_ next: AXUIElement?) {
        if let window, let next, CFEqual(window, next) { return }
        if let observer, let window {
            for name in windowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        window = next
        if let observer, let next {
            AXUIElementSetMessagingTimeout(next, 0.1)
            for name in windowNotifications {
                AXObserverAddNotification(observer, next, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }

    private var windowNotifications: [String] {
        [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
         kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    }

    /// Remove the run-loop source before releasing its unretained callback context.
    func stop() {
        notificationGeneration += 1
        notificationPending = false
        observe(nil)
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        pid = nil
    }
}
