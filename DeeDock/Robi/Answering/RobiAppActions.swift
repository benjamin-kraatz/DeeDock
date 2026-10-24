import AppKit
import ApplicationServices
import Carbon

/// Puts an answer back into the app Robi sits on.
enum RobiAppActions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Replaces the selection in place through Accessibility, the way the app's own text view
    /// would. Works in native text views and in Electron text areas; the spike verified it
    /// across processes.
    static func replace(_ selection: RobiSelection, with text: String) -> Bool {
        AXUIElementSetAttributeValue(selection.element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Pastes through the clipboard and ⌘V, for apps without writable Accessibility text such as
    /// terminals. The person's clipboard is restored a moment later, unless they copied something
    /// new in the meantime.
    static func paste(_ text: String, into processIdentifier: pid_t) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let written = pasteboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
            event?.flags = .maskCommand
            event?.postToPid(processIdentifier)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard pasteboard.changeCount == written else { return }
            restore(saved, to: pasteboard)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        })
    }
}
