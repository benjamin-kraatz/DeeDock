import AppKit
import SwiftUI

/// Borderless panel that covers one display while Harbor is open.
final class HarborPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns one display's Harbor panel.
///
/// The panel sits at the Window Peek stage level, above the menu bar, the macOS Dock, and DOKK's
/// own dock, and joins every Space including full-screen ones. Harbor covers the windows rather
/// than hiding them, so no app changes state when it opens. The panel takes key focus only on the
/// display that holds the search field.
@MainActor
final class HarborPanelController {
    let displayID: String
    private let panel: HarborPanel

    /// - Parameter screenFrame: The display's full frame in AppKit screen coordinates.
    init(displayID: String, screenFrame: CGRect, session: HarborSession, intents: any HarborIntents) {
        self.displayID = displayID
        panel = HarborPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Window frames are offsets from the display's top-left corner, so the content must fill
        // the display exactly; a hosting view that sized the window to its content would shift them.
        let hosting = NSHostingView(rootView: HarborView(session: session, displayID: displayID, intents: intents)
            .frame(width: screenFrame.width, height: screenFrame.height))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(screenFrame, display: false)
    }

    /// Orders the panel in. `key` gives it keyboard focus for search and arrow keys.
    func show(key: Bool) {
        panel.orderFrontRegardless()
        if key { panel.makeKey() }
    }

    /// Takes keyboard focus back, for example after a window's app was activated to close it.
    func reclaimKey() {
        NSApp.activate()
        panel.makeKey()
    }

    func owns(_ window: NSWindow?) -> Bool { window === panel }

    /// Removes the panel for good; the controller is not reused.
    func close() {
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
