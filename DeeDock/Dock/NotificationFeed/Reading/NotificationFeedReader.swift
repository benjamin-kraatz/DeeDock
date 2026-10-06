import AppKit
import ApplicationServices

/// The result of one pass over the NotificationCenter process.
nonisolated struct NotificationFeedPass: Sendable {
    /// Every banner currently on screen, top to bottom, including ones macOS has not filled in yet.
    let readings: [NotificationBannerReading]
    /// False when the change observer could not be registered. No further change signal arrives
    /// until a later pass registers it, so the caller has to retry on its own.
    let observing: Bool
}

/// Reads the banners NotificationCenter is presenting, through the public Accessibility API.
///
/// The structure of NotificationCenter's windows is undocumented. A banner window has subrole
/// `AXSystemDialog`; four levels down, each banner is a group with subrole
/// `AXNotificationCenterBanner` (or `AXNotificationCenterAlert` for system prompts) whose
/// `AXIdentifier` is a per-notification UUID and whose static texts are identified as `title`,
/// `subtitle`, and `body`. Matching uses only roles, subroles, and identifiers, never localized
/// titles. An unrecognized tree yields no readings rather than wrong ones.
///
/// One pass copies attributes on a private serial queue, then resumes this actor. AX handles never
/// leave that queue. The observer's run-loop source stays on the main run loop, and its callback
/// only posts ``changedNotification``.
actor NotificationFeedReader {
    /// Posted on the main thread when NotificationCenter creates a window or changes its layout.
    nonisolated static let changedNotification = Notification.Name("DDockNotificationFeedAXChanged")
    /// The process that presents notification banners.
    nonisolated static let bundleIdentifier = "com.apple.notificationcenterui"

    private let session = NotificationAXSession()

    /// Reads the banners on screen and keeps the change observer registered.
    ///
    /// - Returns: nil when Accessibility is not trusted, or when a pass fails, such as an
    ///   NotificationCenter that does not answer within its messaging timeout. Cancelling the
    ///   caller does not interrupt a pass that has already started.
    func read(pid: pid_t) async -> NotificationFeedPass? {
        guard !Task.isCancelled, AXIsProcessTrusted() else {
            await stop()
            return nil
        }
        return await session.read(pid: pid)
    }

    /// Removes the observer on disable, suspension, or shutdown, even if NotificationCenter is unresponsive.
    func stop() async {
        await session.stop()
    }
}

/// One reader's Accessibility handles.
///
/// `AXUIElementCopyAttributeValue` can block until its messaging timeout. A private queue stalls
/// only this pass; the cooperative pool would hold a thread every task in the app shares (DEE-104).
///
/// `AXUIElement` and `AXObserver` are not `Sendable`, so this conformance is unchecked. Every
/// handle is created, copied, and released on `queue` only. The async methods hop once per call
/// and return plain values. Drop the unchecked conformance if those AX types become `Sendable`.
private nonisolated final class NotificationAXSession: @unchecked Sendable {
    private static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    /// The sidebar's list of older notifications. It shares the window with the widgets and must
    /// never be read as new arrivals.
    private static let sidebarListIdentifier = "AXNotificationListItems"
    /// Banners sit at window > group > group > scroll area > banner.
    private static let maximumDepth = 5
    private static let timeout: Float = 0.2

    private let queue = DispatchQueue(label: "DeeDock.NotificationFeedReads", qos: .utility)
    private var observer: AXObserver?
    private var observedPID: pid_t?

    func read(pid: pid_t) async -> NotificationFeedPass? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: self.pass(for: pid)) }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.releaseObserver()
                continuation.resume()
            }
        }
    }

    private func pass(for pid: pid_t) -> NotificationFeedPass? {
        if observedPID != pid { releaseObserver() }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.timeout)
        // Register before reading, so a banner that arrives during this pass still signals.
        if observer == nil { register(application, pid: pid) }
        do {
            var readings: [NotificationBannerReading] = []
            let windows = try value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            for window in windows {
                // Desktop widgets are windows of the same process with another subrole.
                guard try string(window, kAXSubroleAttribute) == (kAXSystemDialogSubrole as String) else { continue }
                var banners: [AXUIElement] = []
                try collectBanners(in: window, depth: 0, into: &banners)
                for banner in banners {
                    if let reading = try reading(banner) { readings.append(reading) }
                }
            }
            return NotificationFeedPass(readings: readings, observing: observer != nil)
        } catch {
            return nil
        }
    }

    private func collectBanners(in element: AXUIElement, depth: Int, into banners: inout [AXUIElement]) throws {
        if let subrole = try string(element, kAXSubroleAttribute), Self.bannerSubroles.contains(subrole) {
            banners.append(element)
            return
        }
        guard depth < Self.maximumDepth,
              try string(element, kAXIdentifierAttribute) != Self.sidebarListIdentifier else { return }
        for child in try value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            try collectBanners(in: child, depth: depth + 1, into: &banners)
        }
    }

    private func reading(_ banner: AXUIElement) throws -> NotificationBannerReading? {
        guard let id = try string(banner, kAXIdentifierAttribute), !id.isEmpty else { return nil }
        var texts: [String: String] = [:]
        for child in try value(banner, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard try string(child, kAXRoleAttribute) == (kAXStaticTextRole as String),
                  let identifier = try string(child, kAXIdentifierAttribute),
                  let text = try string(child, kAXValueAttribute) else { continue }
            texts[identifier] = text
        }
        return NotificationBannerReading(id: id, description: try string(banner, kAXDescriptionAttribute),
                                         title: texts["title"], subtitle: texts["subtitle"], body: texts["body"])
    }

    private func string(_ element: AXUIElement, _ attribute: String) throws -> String? {
        try value(element, attribute) as? String
    }

    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        // AX timeouts belong to each handle; the application's timeout does not cover its children.
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        switch error {
        case .success: return result
        // A banner can finish its exit animation mid-pass. Its vanished elements are skipped.
        case .noValue, .attributeUnsupported, .invalidUIElement: return nil
        default: throw NSError(domain: "DDockNotificationFeedAccessibility", code: Int(error.rawValue))
        }
    }

    /// Observes the application element, so new banner windows and banners added to an existing
    /// window both signal. A second banner that arrives while the first is on screen reuses its
    /// window and posts only a layout change.
    private func register(_ application: AXUIElement, pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            NotificationCenter.default.post(name: NotificationFeedReader.changedNotification, object: nil)
        }, &created) == .success, let created else { return }
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification] {
            guard AXObserverAddNotification(created, application, name as CFString, nil) == .success else { return }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedPID = pid
    }

    /// Releasing the observer removes its subscriptions without an IPC call per notification.
    private func releaseObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }
}
