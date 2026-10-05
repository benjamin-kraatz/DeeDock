import AppKit
import ApplicationServices

/// Reads only the system Dock's application items.
///
/// One pass copies attributes on a private serial queue, then resumes this actor.
/// AX handles never leave that queue. The observer run-loop source stays on the main run loop.
/// AXStatusLabel is a Dock-provided attribute, not a documented cross-app badge API.
actor DockBadgeReader {
    private let session = BadgeAXSession()

    /// Returns a complete snapshot keyed by canonical application path.
    ///
    /// Without Accessibility trust or a running Dock, the snapshot is empty because no badge can
    /// be observed. Returns `nil` when a scan throws, such as a 0.15 s child timeout, so the
    /// caller can tell a transient failure from a Dock without badges. Cancelling the caller
    /// does not interrupt a pass that has already started.
    func read(pid: pid_t?) async -> [String: BadgeObservation]? {
        guard !Task.isCancelled, AXIsProcessTrusted(), let pid else {
            await stop()
            return [:]
        }
        return await session.read(pid: pid)
    }

    /// Removes observation on disable, restart, or shutdown, even if the Dock is unresponsive.
    func stop() async {
        await session.stop()
    }
}

/// One badge pass's Accessibility handles.
///
/// `AXUIElementCopyAttributeValue` can block until its 0.15 s messaging timeout. A private
/// queue stalls only this pass. The cooperative pool would hold one of the few threads every
/// task in the app shares, which is the same reason `VolumeReads` exists.
///
/// `AXUIElement` and `AXObserver` are not `Sendable`, so this conformance is unchecked. Every
/// handle is created, copied, and released on `queue` only. The async methods hop once per call
/// and return `BadgeObservation` values. The observer run-loop source is installed on the main
/// run loop, not on `queue`. Drop the unchecked conformance if those AX types become `Sendable`.
private nonisolated final class BadgeAXSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "DeeDock.BadgeReads", qos: .utility)
    private var observer: AXObserver?
    private var dockPID: pid_t?
    private var observed: [AXUIElement] = []

    /// Copies one full pass, then resumes the caller. One hop, not one hop per attribute.
    func read(pid: pid_t) async -> [String: BadgeObservation]? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: self.snapshot(for: pid)) }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.releaseObserver()
                self.dockPID = nil
                continuation.resume()
            }
        }
    }

    private func snapshot(for pid: pid_t) -> [String: BadgeObservation]? {
        if dockPID != pid {
            releaseObserver()
            dockPID = pid
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        do {
            var items: [AXUIElement] = []
            let children = try value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children {
                if try value(child, kAXRoleAttribute) as? String == kAXListRole {
                    items += try value(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
            }
            var result: [String: BadgeObservation] = [:]
            var applications: [AXUIElement] = []
            for item in items {
                guard try value(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { continue }
                applications.append(item)
                guard let rawURL = try value(item, kAXURLAttribute) else { continue }
                let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:))
                guard let url, url.isFileURL else { continue }
                // Same queue as the AX copies. Resolving the path must not move this pass off the queue.
                let path = DockBadgePath.key(for: url)
                let observation = try badgeValue(item)
                // Multiple Dock items for one installation must agree. Never sum process badges.
                if let previous = result[path], previous != observation { result[path] = .unknown }
                else { result[path] = observation }
            }
            // The one-second budget covers registration only, so a long item walk still returns.
            updateObservation([root] + applications, pid: pid,
                              deadline: ContinuousClock.now.advanced(by: .seconds(1)))
            return result
        } catch {
            releaseObserver()
            dockPID = nil
            return nil
        }
    }

    private func badgeValue(_ element: AXUIElement) throws -> BadgeObservation {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, "AXStatusLabel" as CFString, &result)
        switch error {
        case .success:
            return (result as? String).map(BadgeObservation.init(label:)) ?? .unknown
        case .noValue: return .cleared
        case .attributeUnsupported: return .unknown
        default: throw NSError(domain: "DDockBadgeAccessibility", code: Int(error.rawValue))
        }
    }

    private func check(_ deadline: ContinuousClock.Instant) throws {
        if ContinuousClock.now >= deadline { throw CancellationError() }
    }

    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        // AX timeouts belong to this exact handle; the root timeout does not cover children.
        AXUIElementSetMessagingTimeout(element, 0.15)
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
}
