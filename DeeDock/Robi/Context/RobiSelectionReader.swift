import ApplicationServices

/// Text the person selected in another app, and whether Robi may replace it.
struct RobiSelection {
    let text: String
    /// The focused element holding the selection. Replacing writes `kAXSelectedTextAttribute` here.
    let element: AXUIElement
    let isReplaceable: Bool
}

/// Reads the current selection without touching the clipboard.
///
/// Clicking Robi's non-activating panel leaves the app frontmost, so its focused element and
/// selection are still the ones the person made.
enum RobiSelectionReader {
    static func selection(processIdentifier: pid_t) -> RobiSelection? {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let focused = RobiAX.element(application, kAXFocusedUIElementAttribute) else { return nil }
        if let text = RobiAX.value(focused, kAXSelectedTextAttribute) as? String, Self.hasContent(text) {
            return RobiSelection(text: text, element: focused,
                                 isReplaceable: RobiAX.isSettable(focused, kAXSelectedTextAttribute))
        }
        // WebKit and Chromium report a selection in web content through text markers.
        if let range = RobiAX.value(focused, "AXSelectedTextMarkerRange") {
            var string: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, range, &string) == .success,
               let text = string as? String, Self.hasContent(text) {
                return RobiSelection(text: text, element: focused, isReplaceable: false)
            }
        }
        return nil
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
