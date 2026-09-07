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
    func read(pid: pid_t?) async -> [String: String] {
        guard !Task.isCancelled, AXIsProcessTrusted(), let pid else { stop(); return [:] }
        if dockPID != pid {
            stop()
            dockPID = pid
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        do {
            var items: [AXUIElement] = []
            let children = try value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children {
                try Task.checkCancellation()
                if try value(child, kAXRoleAttribute) as? String == kAXListRole {
                    items += try value(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
            }
            var result: [String: String] = [:]
            var applications: [AXUIElement] = []
            for (index, item) in items.enumerated() {
                // Valid large Docks must not lose every badge just because a complete scan
                // takes over a second. Small batches release the executor between AX calls.
                if index > 0 && index.isMultiple(of: 16) {
                    try await Task.sleep(for: .milliseconds(25))
                }
                try Task.checkCancellation()
                guard try value(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { continue }
                applications.append(item)
                // Most apps have no badge; do not query their URL on every fallback scan.
                guard let label = try value(item, "AXStatusLabel") as? String,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                try Task.checkCancellation()
                guard let rawURL = try value(item, kAXURLAttribute) else { continue }
                let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:))
                guard let url, url.isFileURL else { continue }
                result[url.standardizedFileURL.path] = label
            }
            updateObservation([root] + applications, pid: pid,
                              deadline: ContinuousClock.now.advanced(by: .seconds(1)))
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
        // AX timeouts belong to this exact handle; the root timeout does not cover children.
        AXUIElementSetMessagingTimeout(element, 0.15)
        try Task.checkCancellation()
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        switch error {
        case .success: return result
        case .noValue, .attributeUnsupported: return nil
        default: throw NSError(domain: "DDockBadgeAccessibility", code: Int(error.rawValue))
        }
    }

    private func updateObservation(_ elements: [AXUIElement], pid: pid_t,
                                   deadline: ContinuousClock.Instant) {
        guard observer == nil || observed.count != elements.count
            || !zip(observed, elements).allSatisfy({ CFEqual($0, $1) }) else { return }
        releaseObserver()
        do {
            try check(deadline)
            var created: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, _ in
                NotificationCenter.default.post(name: Notification.Name("DDockBadgeAXChanged"), object: nil)
            }, &created) == .success, let created else { return }
            observer = created
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.15)
                for name in notificationNames {
                    try check(deadline)
                    // Unsupported subscriptions use the slow fallback. A failed registration
                    // never discards a successfully read badge snapshot.
                    AXObserverAddNotification(created, element, name as CFString, nil)
                }
            }
            observed = elements
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        } catch {
            releaseObserver()
        }
    }

    private var notificationNames: [String] {
        [kAXValueChangedNotification, kAXTitleChangedNotification, kAXLayoutChangedNotification]
    }

    /// Releasing the observer removes its subscriptions without one IPC call per old item.
    private func releaseObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observed = []
    }

    /// Removes observation on disable, restart, or shutdown, even if the Dock is unresponsive.
    func stop() {
        releaseObserver()
        dockPID = nil
    }
}
