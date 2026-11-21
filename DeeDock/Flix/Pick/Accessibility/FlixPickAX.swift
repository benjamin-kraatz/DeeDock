import ApplicationServices
import Foundation

/// The Accessibility reads and writes Flix Pick makes, all inside a system picker.
///
/// **Privacy rule.** Nothing is read from a window or sheet unless its `AXIdentifier` is exactly
/// `open-panel` or `save-panel` (``pickerKind(of:)``). To find a picker, only the focused window's
/// identifier and the roles and identifiers of its direct children (a sheet is a child of its
/// window) are looked at; no title, value, or text of any other window is ever read. Inside the
/// picker, Flix Pick reads control identifiers, frames, the default button's title, the current
/// folder's name (`where popup`), and the `AXURL` of file rows; it writes only the list's selection
/// and the Go to Folder field (`PathTextField`), and presses only `OKButton`.
///
/// The identifiers are macOS's own, proven on macOS 27 by two probes, and not public API: every
/// one is looked up, never assumed, and a missing one leaves its route out (see `FlixPickRouter`).
/// Call everything on ``FlixAXThread``; each element carries a messaging timeout.
nonisolated enum FlixPickAX {
    static let messagingTimeout: Float = 0.25

    static let okButton = "OKButton"
    static let cancelButton = "CancelButton"
    static let listView = "ListView"
    static let columnView = "ColumnView"
    static let wherePopup = "where popup"
    static let pathField = "PathTextField"

    static func identifier(_ element: AXUIElement) -> String? {
        RobiAX.value(element, kAXIdentifierAttribute) as? String
    }

    static func role(_ element: AXUIElement) -> String? {
        RobiAX.value(element, kAXRoleAttribute) as? String
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        RobiAX.value(element, attribute) as? String
    }

    /// Whether the element still exists in its app.
    static func isAlive(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return error != .invalidUIElement && error != .cannotComplete
    }

    /// The picker kind of a window or sheet, from its identifier alone.
    static func pickerKind(of element: AXUIElement) -> FlixPickPickerKind? {
        FlixPickPickerKind(identifier: identifier(element))
    }

    /// The picker in `window`: the window itself, or a sheet on it. Reads only the window's
    /// identifier and its direct children's roles; a child is looked at further only when it is a
    /// sheet, and then only for its identifier.
    static func picker(in window: AXUIElement) -> (element: AXUIElement, kind: FlixPickPickerKind, parent: AXUIElement?)? {
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        if let kind = pickerKind(of: window) { return (window, kind, nil) }
        for child in RobiAX.children(window).prefix(64) where role(child) == kAXSheetRole as String {
            AXUIElementSetMessagingTimeout(child, messagingTimeout)
            if let kind = pickerKind(of: child) { return (child, kind, window) }
        }
        return nil
    }

    /// The picker's controls Flix Pick uses, by identifier. Walks the picker's container structure
    /// breadth first, never into lists, outlines, tables, browsers, or rows, so a folder with
    /// thousands of files costs nothing. At most 400 elements, 14 levels deep.
    static func controls(in picker: AXUIElement) -> [String: AXUIElement] {
        let wanted: Set<String> = [okButton, cancelButton, listView, columnView, wherePopup]
        let leaves: Set<String> = [kAXOutlineRole, kAXTableRole, kAXBrowserRole, kAXListRole, kAXRowRole,
                                   kAXTextAreaRole, "AXWebArea"]
        var found: [String: AXUIElement] = [:]
        var queue: [(AXUIElement, Int)] = RobiAX.children(picker).map { ($0, 1) }
        var visited = 0
        while !queue.isEmpty, visited < 400, found.count < wanted.count {
            let (element, depth) = queue.removeFirst()
            visited += 1
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            if let id = identifier(element), wanted.contains(id), found[id] == nil { found[id] = element }
            guard depth < 14, let role = role(element), !leaves.contains(role) else { continue }
            queue.append(contentsOf: RobiAX.children(element).map { ($0, depth + 1) })
        }
        return found
    }

    /// The file a list row stands for: the `AXURL` of the text field in its first cells.
    static func url(ofRow row: AXUIElement) -> URL? {
        var queue: [(AXUIElement, Int)] = [(row, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 12 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if depth > 0, let value = RobiAX.value(element, kAXURLAttribute) {
                if let url = value as? URL { return url }
            }
            guard depth < 3 else { continue }
            queue.append(contentsOf: RobiAX.children(element).prefix(6).map { ($0, depth + 1) })
        }
        return nil
    }

    /// The file of the first selected row in the list.
    static func selectedURL(in list: AXUIElement) -> URL? {
        guard let rows = RobiAX.value(list, kAXSelectedRowsAttribute) as? [AXUIElement], let first = rows.first else {
            return nil
        }
        return url(ofRow: first)
    }

    static func frame(_ element: AXUIElement) -> CGRect? { RobiAX.frame(of: element) }

    /// The frame a list is seen through: its scroll area, else the list itself.
    static func visibleFrame(ofList list: AXUIElement) -> CGRect? {
        if let parent = RobiAX.element(list, kAXParentAttribute), role(parent) == kAXScrollAreaRole as String {
            return frame(parent)
        }
        return frame(list)
    }

    /// Two file URLs name the same file or folder (ignoring a trailing slash and `..` spellings).
    static func same(_ url: URL, _ path: String) -> Bool {
        FlixPaths.standardized(url.standardizedFileURL.path) == FlixPaths.standardized(path)
    }
}
