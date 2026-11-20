import ApplicationServices
import Dispatch

/// The Accessibility reads and writes behind Drop to Place.
///
/// Every frame here is in the Quartz top-left space Accessibility uses: x is shared with AppKit,
/// y is measured down from the top of the main display (`CGMainDisplayID`). Callers convert at
/// this boundary with `AppMeltGeometry.quartz(fromAppKit:)` and `AppMeltGeometry.appKit(_:primaryTop:)`.
///
/// AX messages can block until their timeout, so, like `AccessibilityApplicationWindowService`,
/// this actor runs on its own serial queue instead of the shared cooperative pool. No
/// `AXUIElement` leaves the actor. Nothing here runs on the pointer path: the drag reads one
/// frame when it starts, and placement writes once after release.
actor DropPlacementAccessibility {
    private nonisolated let queue = DispatchSerialQueue(label: "DeeDock.DropPlacement")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    /// Seconds an unresponsive app may hold each message. Launching apps are often busy.
    private let messagingTimeout: Float = 0.5

    /// The app's front window frame: focused, else main, else its first standard window.
    /// Nil without Accessibility access, or while the app has no window.
    func frontWindowFrame(processIdentifier: pid_t) -> CGRect? {
        guard AXIsProcessTrusted(), let window = frontWindow(processIdentifier) else { return nil }
        return rect(window)
    }

    /// Moves and resizes the front window to `frame`, then reads the result back.
    ///
    /// Position is written first so the size is negotiated on the destination display, then size,
    /// then position again because some apps shift a window while resizing it.
    /// - Parameter deadline: When given, nothing is written once it has passed. Checked after the
    ///   window lookup, which can itself wait for a busy app.
    /// - Returns: The frame the app accepted, or nil when there is no window, the deadline passed,
    ///   or a write failed.
    func setFrontWindowFrame(processIdentifier: pid_t, to frame: CGRect,
                             deadline: ContinuousClock.Instant? = nil) throws -> CGRect? {
        try Task.checkCancellation()
        guard AXIsProcessTrusted(), let window = frontWindow(processIdentifier) else { return nil }
        if let deadline, ContinuousClock.now >= deadline { return nil }
        var origin = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return nil }
        let positionStatus = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        try Task.checkCancellation()
        let sizeStatus = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        if positionStatus == .success || sizeStatus == .success {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        guard positionStatus == .success || sizeStatus == .success else { return nil }
        return rect(window)
    }

    private func frontWindow(_ processIdentifier: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = copy(application, attribute as CFString), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                if isWindow(window) { return window }
            }
        }
        guard let windows = copy(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return nil }
        return windows.first { isWindow($0) && string($0, kAXSubroleAttribute as CFString) == kAXStandardWindowSubrole }
    }

    private func isWindow(_ element: AXUIElement) -> Bool {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return string(element, kAXRoleAttribute as CFString) == kAXWindowRole
    }

    private func copy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value : nil
    }

    private func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copy(element, attribute) as? String
    }

    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute as CFString),
              let sizeValue = copy(element, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
