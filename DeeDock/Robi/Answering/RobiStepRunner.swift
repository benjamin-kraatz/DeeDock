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

    /// Runs `step` in the app with `processIdentifier`. Returns false when its target is gone,
    /// changed, or refused the action.
    static func run(_ step: RobiStep, processIdentifier: pid_t, elements: [Int: AXUIElement]) -> Bool {
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
            // Some controls report their new state a moment late; trust the press then.
            return isOn(element).map { $0 == on } ?? true
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

    /// A checkbox, switch or option's state: its value is 1 when on or selected.
    private static func isOn(_ element: AXUIElement) -> Bool? {
        (RobiAX.value(element, kAXValueAttribute) as? NSNumber).map { $0.intValue == 1 }
    }
}
