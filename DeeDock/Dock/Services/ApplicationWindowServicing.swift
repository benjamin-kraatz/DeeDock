import ApplicationServices
import AppKit
import Security

/// Failures from public Accessibility window discovery and control.
nonisolated enum ApplicationWindowServiceError: Error, Equatable, Sendable {
    case permissionRequired
    case sandboxRestricted
    case applicationUnavailable
    case windowUnavailable
    case accessibility(Int32)
}

/// Actor ownership keeps native Accessibility elements serialized and out of UI-facing values.
protocol ApplicationWindowServicing: Actor {
    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws -> [ApplicationWindowSummary]
    func selectWindow(_ token: ApplicationWindowToken) async throws
    func discard(sessionID: UUID)
    func stop()
}

/// Public AX window access with bounded cross-process messaging.
actor AccessibilityApplicationWindowService: ApplicationWindowServicing {
    private struct Handle {
        let element: AXUIElement
        let processIdentifier: pid_t
    }

    private var handles: [ApplicationWindowToken: Handle] = [:]
    private let messagingTimeout: Float

    init(messagingTimeout: Float = 0.25) {
        self.messagingTimeout = messagingTimeout
    }

    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws -> [ApplicationWindowSummary] {
        guard AXIsProcessTrusted() else { throw ApplicationWindowServiceError.permissionRequired }
        do {
            return try discoverTrusted(processes: processes, sessionID: sessionID)
        } catch let error as ApplicationWindowServiceError {
            if Self.isSandboxed, case .accessibility = error {
                throw ApplicationWindowServiceError.sandboxRestricted
            }
            throw error
        }
    }

    private func discoverTrusted(processes: [ApplicationProcessSnapshot], sessionID: UUID) throws
        -> [ApplicationWindowSummary] {
        handles = handles.filter { $0.key.sessionID != sessionID }
        var result: [ApplicationWindowSummary] = []

        for process in processes {
            try Task.checkCancellation()
            let application = AXUIElementCreateApplication(process.processIdentifier)
            _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
            guard let windows = try copy(application, attribute: kAXWindowsAttribute as CFString) as? [AXUIElement] else { continue }

            for window in windows {
                try Task.checkCancellation()
                guard string(window, attribute: kAXRoleAttribute as CFString) == kAXWindowRole else { continue }
                let subrole = string(window, attribute: kAXSubroleAttribute as CFString)
                if subrole == kAXFloatingWindowSubrole || subrole == kAXSystemFloatingWindowSubrole { continue }

                let token = ApplicationWindowToken(sessionID: sessionID, id: UUID())
                handles[token] = Handle(element: window, processIdentifier: process.processIdentifier)
                let rawTitle = string(window, attribute: kAXTitleAttribute as CFString)
                result.append(ApplicationWindowSummary(
                    token: token,
                    processIdentifier: process.processIdentifier,
                    title: rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle : nil,
                    frame: rect(window),
                    isMinimized: boolean(window, attribute: kAXMinimizedAttribute as CFString) ?? false,
                    isMain: boolean(window, attribute: kAXMainAttribute as CFString) ?? false
                ))
            }
        }
        return result
    }

    func selectWindow(_ token: ApplicationWindowToken) async throws {
        guard AXIsProcessTrusted() else { throw ApplicationWindowServiceError.permissionRequired }
        guard let handle = handles[token] else {
            throw ApplicationWindowServiceError.windowUnavailable
        }
        // Every token is scoped to one menu presentation. Taking any row invalidates its siblings.
        handles = handles.filter { $0.key.sessionID != token.sessionID }
        guard let application = NSRunningApplication(processIdentifier: handle.processIdentifier),
              !application.isTerminated else {
            throw ApplicationWindowServiceError.windowUnavailable
        }

        if boolean(handle.element, attribute: kAXMinimizedAttribute as CFString) == true,
           isSettable(handle.element, attribute: kAXMinimizedAttribute as CFString) {
            try set(handle.element, attribute: kAXMinimizedAttribute as CFString, value: kCFBooleanFalse)
        }
        guard application.activate(options: []) else {
            throw ApplicationWindowServiceError.applicationUnavailable
        }
        if isSettable(handle.element, attribute: kAXMainAttribute as CFString) {
            try set(handle.element, attribute: kAXMainAttribute as CFString, value: kCFBooleanTrue)
        }
        try check(AXUIElementPerformAction(handle.element, kAXRaiseAction as CFString))
    }

    func discard(sessionID: UUID) {
        handles = handles.filter { $0.key.sessionID != sessionID }
    }

    func stop() { handles.removeAll() }

    private func copy(_ element: AXUIElement, attribute: CFString) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .attributeUnsupported || error == .noValue { return nil }
        try check(error)
        return value
    }

    private func string(_ element: AXUIElement, attribute: CFString) -> String? {
        (try? copy(element, attribute: attribute)) as? String
    }

    private func boolean(_ element: AXUIElement, attribute: CFString) -> Bool? {
        guard let value = try? copy(element, attribute: attribute) else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = try? copy(element, attribute: kAXPositionAttribute as CFString),
              let sizeValue = try? copy(element, attribute: kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private func set(_ element: AXUIElement, attribute: CFString, value: CFTypeRef) throws {
        try check(AXUIElementSetAttributeValue(element, attribute, value))
    }

    private func check(_ error: AXError) throws {
        guard error != .success else { return }
        throw ApplicationWindowServiceError.accessibility(error.rawValue)
    }

    /// TCC trust and App Sandbox policy are separate checks. A signed sandboxed build can pass
    /// `AXIsProcessTrusted` while cross-process AX calls remain unavailable.
    private static var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.security.app-sandbox" as CFString, nil
              ) else { return false }
        return value as? Bool == true
    }
}
