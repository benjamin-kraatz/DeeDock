import AppKit
import SwiftUI

/// The borderless, non-activating panel that holds Robi's tab, prompt bar and answer card.
///
/// Hovering and clicking never activate DOKK, so the app underneath stays frontmost and keeps its
/// selection. While the person types a question the panel becomes key without activating DOKK:
/// the spike confirmed keystrokes reach the prompt field while the app keeps the menu bar.
final class RobiPanel: NSPanel {
    /// Only true while a text field in the panel needs the keyboard.
    var allowsKey = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 132, height: 52),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Joins every Space so it can follow the focused window there, sits on full-screen Spaces,
        // and as a transient window is hidden by Mission Control instead of floating over it.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI in Robi's panels: takes the first click without activating DOKK and reports
/// hover from a tracking area that stays active while another app is frontmost.
final class RobiHostingView<Content: View>: NSHostingView<Content> {
    var hoverChanged: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); hoverChanged?(false) }
}
