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
}

/// Hosts the Hub's SwiftUI content. Accepts the first click while DOKK is inactive, so a click on
/// a tile or row acts immediately instead of only activating the window.
final class HubHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
