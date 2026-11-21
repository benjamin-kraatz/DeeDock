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

    /// A time limit shared by every Accessibility call of one operation, so a picker that answers
    /// slowly (a folder on a network share) cannot hold the thread for long. Each call also carries
    /// ``messagingTimeout``.
    nonisolated struct Deadline {
        let end: CFAbsoluteTime

        init(seconds: Double) { end = CFAbsoluteTimeGetCurrent() + seconds }

        var passed: Bool { CFAbsoluteTimeGetCurrent() >= end }
    }

    /// `element`'s children, each with the messaging timeout set before it is queried.
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        timed(RobiAX.children(element))
    }

    /// An element-valued attribute, with the messaging timeout set on the element it returns.
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let found = RobiAX.element(element, attribute) else { return nil }
        AXUIElementSetMessagingTimeout(found, messagingTimeout)
        return found
    }

    /// An element-list attribute (rows, selected rows), each with the messaging timeout set.
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        (RobiAX.value(element, attribute) as? [AXUIElement]).map(timed)
    }

    private static func timed(_ elements: [AXUIElement]) -> [AXUIElement] {
        for element in elements { AXUIElementSetMessagingTimeout(element, messagingTimeout) }
        return elements
    }

    /// The actions an element offers.
    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    /// The picker's controls Flix Pick uses, by identifier. Walks the picker's container structure
    /// breadth first, never into lists, outlines, tables, browsers, or rows, so a folder with
    /// thousands of files costs nothing. At most 400 elements, 14 levels deep, half a second.
    static func controls(in picker: AXUIElement) -> [String: AXUIElement] {
        let wanted: Set<String> = [okButton, cancelButton, listView, columnView, wherePopup]
        let leaves: Set<String> = [kAXOutlineRole, kAXTableRole, kAXBrowserRole, kAXListRole, kAXRowRole,
                                   kAXTextAreaRole, "AXWebArea"]
        let deadline = Deadline(seconds: 0.5)
        var found: [String: AXUIElement] = [:]
        var queue: [(AXUIElement, Int)] = children(picker).map { ($0, 1) }
        var visited = 0
        while !queue.isEmpty, visited < 400, found.count < wanted.count, !deadline.passed {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if let id = identifier(element), wanted.contains(id), found[id] == nil { found[id] = element }
            guard depth < 14, let role = role(element), !leaves.contains(role) else { continue }
            queue.append(contentsOf: children(element).map { ($0, depth + 1) })
        }
        return found
    }

    /// The file a list row stands for: the `AXURL` of the text field in its first cells.
    static func url(ofRow row: AXUIElement, deadline: Deadline) -> URL? {
        var queue: [(AXUIElement, Int)] = [(row, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 12, !deadline.passed {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if depth > 0, let url = RobiAX.value(element, kAXURLAttribute) as? URL { return url }
            guard depth < 3 else { continue }
            queue.append(contentsOf: children(element).prefix(6).map { ($0, depth + 1) })
        }
        return nil
    }

    /// How many rows the list has selected, and the file when exactly one is.
    static func selection(in list: AXUIElement, deadline: Deadline) -> (count: Int, url: URL?) {
        let rows = elements(list, kAXSelectedRowsAttribute) ?? []
        guard rows.count == 1 else { return (rows.count, nil) }
        return (1, url(ofRow: rows[0], deadline: deadline))
    }

    /// The folder the list shows, from its first row's parent. Nil for an empty folder or a list
    /// that cannot be read: a folder's name (the popup) is never proof of its place.
    static func listedFolder(in list: AXUIElement, deadline: Deadline) -> URL? {
        guard let first = elements(list, kAXRowsAttribute)?.first,
              let url = url(ofRow: first, deadline: deadline) else { return nil }
        return url.deletingLastPathComponent()
    }

    /// The Go to Folder sheet a field sits in: its nearest sheet or window ancestor, when that is
    /// not the picker itself (whose default button is the picker's Open or Save).
    static func goToSheet(of field: AXUIElement, picker: AXUIElement) -> AXUIElement? {
        var ancestor = element(field, kAXParentAttribute)
        for _ in 0..<12 {
            guard let current = ancestor else { return nil }
            if CFEqual(current, picker) { return nil }
            let role = role(current)
            if role == kAXSheetRole as String || role == kAXWindowRole as String { return current }
            ancestor = element(current, kAXParentAttribute)
        }
        return nil
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
