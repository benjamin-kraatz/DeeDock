import AppKit
import SwiftUI

/// The Hub's one window: a borderless, nonactivating panel while anchored to the DOKK tile, and a
/// titled, resizable, movable panel while detached.
///
/// It can become key so the header search field and the tabs receive the keyboard; it never
/// becomes main, so the app that was frontmost keeps its main window. Being an `NSPanel` also
/// keeps the detached Hub out of DOKK's own Dock presence (see `AppDockPresence`).
final class HubPanel: NSPanel {
    /// Called after the panel stops being key.
    var resignedKey: (() -> Void)?
    /// The title bar's close button and ⌘W. Returning false keeps AppKit from closing the panel;
    /// the owner animates it away instead.
    var closeRequested: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }

    /// The traffic-light close button routes here. The owner decides how the Hub closes.
    override func performClose(_ sender: Any?) {
        if let closeRequested { closeRequested() } else { super.performClose(sender) }
    }

    /// Escape that no view consumed. The shell's key monitor handles Escape first; this keeps
    /// AppKit from beeping when it falls through.
    override func cancelOperation(_ sender: Any?) {}

    /// Text drags the field editor takes: plain text, RTF and HTML, which it inserts as text.
    static let fieldEditorDragTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .html]

    /// Keeps file and picture drags out of the Hub's text fields.
    ///
    /// While a text field edits, AppKit's field editor (an `NSTextView`) registers for file URLs, filenames, web
    /// URLs and pictures as well as text, and inserts a dropped file as its path. AppKit gives a drag to the deepest
    /// view under the pointer that registered for one of its types, so the field editor would take every file
    /// dragged over the header's search field before that field's own drop target could (the Files tab searches with
    /// a dropped picture or indexed file, `HubSearchExtras`). Registering the editor for text types only lets those
    /// drags fall through to the SwiftUI drop targets behind it, which take or refuse them; plain text still drops in
    /// as text.
    ///
    /// The window's field editor is the system's and is reused for every field, and it registers its types again
    /// whenever editing begins, which happens inside this call. So the registration is narrowed after every change
    /// of first responder, never by replacing the system's field editor.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let changed = super.makeFirstResponder(responder)
        if let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            editor.unregisterDraggedTypes()
            editor.registerForDraggedTypes(Self.fieldEditorDragTypes)
        }
        return changed
    }
}

/// Hosts the Hub's SwiftUI content. Accepts the first click while DOKK is inactive, so a click on
/// a tile or row acts immediately instead of only activating the window.
final class HubHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
