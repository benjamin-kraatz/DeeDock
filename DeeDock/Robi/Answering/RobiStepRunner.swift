import ApplicationServices
import Foundation

/// Runs the steps of a proposal in the app, through Accessibility, after the person clicked Run.
///
/// Every step checks its target again first: a menu item must still exist and be enabled, and a
/// window element must still answer with the role and label it had when the window was read. A
/// step that fails stops the chain, so later steps never run on a window that has changed under
/// them. Nothing here activates DOKK or moves the pointer.
@MainActor
enum RobiStepRunner {
    /// The pause between steps, so the app can react to one before the next, such as a field
    /// updating a button's state after typing.
    static let pause: Duration = .milliseconds(250)

    /// How long a toggle may take to report its new state after the press.
    private static let settleTime: Duration = .milliseconds(600)

    /// Runs `step` in the app with `processIdentifier`. Returns false when its target is gone,
    /// changed, or refused the action. Suspends only while a toggle settles.
    static func run(_ step: RobiStep, processIdentifier: pid_t, elements: [Int: AXUIElement]) async -> Bool {
        switch step {
        case let .menu(path):
            return RobiMenuCommands.press(processIdentifier: processIdentifier, path: path)
        case let .press(id, label):
            guard let element = check(elements[id], label: label) else { return false }
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        case let .toggle(id, label, on):
            guard let element = check(elements[id], label: label) else { return false }
            if isOn(element) == on { return true }
            guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { return false }
            return await settles(element, on: on)
        case let .type(id, label, text):
            guard let element = check(elements[id], label: label) else { return false }
            // Focus first: web fields and search fields often act on text only while focused.
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
        }
    }

    /// The element, if it still has its role and, for a control, its label. A field's label is
    /// usually its text, which may have changed since, so only its role is checked.
    private static func check(_ element: AXUIElement?, label: String) -> AXUIElement? {
        guard let element else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let role = RobiAX.value(element, kAXRoleAttribute) as? String, let kind = RobiLandmark.Kind(role: role) else { return nil }
        if kind.isEditable { return element }
        if (RobiAX.value(element, kAXEnabledAttribute) as? Bool) == false { return nil }
        return RobiWindowText.label(of: element, kind: kind) == label ? element : nil
    }

    /// Whether a pressed toggle reaches `on`. Many apps, SwiftUI among them, update the value a
    /// moment after the press, so the old state reads back at first; it is read again until it
    /// changes or `settleTime` runs out, and only a state still wrong then fails the step. A state
    /// that cannot be read at all, such as a checkbox whose press rebuilt the view around it,
    /// falls back on the press, which the app accepted.
    private static func settles(_ element: AXUIElement, on: Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: settleTime)
        while true {
            guard let state = isOn(element) else { return true }
            if state == on { return true }
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A checkbox, switch or option's state: its value is 1 when on or selected.
    private static func isOn(_ element: AXUIElement) -> Bool? {
        (RobiAX.value(element, kAXValueAttribute) as? NSNumber).map { $0.intValue == 1 }
    }
}
