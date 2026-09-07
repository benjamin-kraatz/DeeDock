import AppKit
import ApplicationServices

/// Reads only the system Dock's application items. AX handles never leave this actor.
/// AXStatusLabel is a Dock-provided attribute, not a documented cross-app badge API.
actor DockBadgeReader {
    private var observer: AXObserver?
    private var dockPID: pid_t?
    private var observed: [AXUIElement] = []

    /// Returns a complete snapshot keyed by standardized application URL. Any failed scan clears
    /// the snapshot rather than keeping a count which may no longer be true.
    func read(pid: pid_t?) -> [String: String] {
        guard !Task.isCancelled, AXIsProcessTrusted(), let pid else { stop(); return [:] }
        if dockPID != pid {
            stop()
            dockPID = pid
            var created: AXObserver?
            if AXObserverCreate(pid, { _, _, _, _ in
                NotificationCenter.default.post(name: Notification.Name("DDockBadgeAXChanged"), object: nil)
            }, &created) == .success, let created {
                observer = created
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            }
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        do {
            var items: [AXUIElement] = []
            let children = try value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children {
                try check(deadline)
                if try value(child, kAXRoleAttribute) as? String == kAXListRole {
                    items += try value(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
            }
            var result: [String: String] = [:]
            var applications: [AXUIElement] = []
            for item in items.prefix(256) {
                try check(deadline)
                guard try value(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { continue }
                applications.append(item)
                guard let rawURL = try value(item, kAXURLAttribute) else { continue }
                let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:))
                guard let url, url.isFileURL,
                      let label = try value(item, "AXStatusLabel") as? String,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                result[url.standardizedFileURL.path] = label
            }
            updateObservation([root] + applications)
            return result
        } catch {
            stop()
            return [:]
        }
    }

    private func check(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        if ContinuousClock.now >= deadline { throw CancellationError() }
    }

    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        switch error {
        case .success: return result
        case .noValue, .attributeUnsupported: return nil
        default: throw NSError(domain: "DDockBadgeAccessibility", code: Int(error.rawValue))
        }
    }

    private func updateObservation(_ elements: [AXUIElement]) {
        guard let observer else { return }
        guard observed.count != elements.count || !zip(observed, elements).allSatisfy({ CFEqual($0, $1) }) else { return }
        for element in observed {
            for name in notificationNames { AXObserverRemoveNotification(observer, element, name as CFString) }
        }
        observed = elements
        for element in elements {
            // Unsupported subscriptions are harmless: the slow fallback still refreshes badges.
            for name in notificationNames { AXObserverAddNotification(observer, element, name as CFString, nil) }
        }
    }

    private var notificationNames: [String] {
        [kAXValueChangedNotification, kAXTitleChangedNotification, kAXLayoutChangedNotification]
    }

    /// Removes the run-loop source and every subscription on disable, restart, or shutdown.
    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            for element in observed {
                for name in notificationNames { AXObserverRemoveNotification(observer, element, name as CFString) }
            }
        }
        observer = nil
        observed = []
        dockPID = nil
    }
}
