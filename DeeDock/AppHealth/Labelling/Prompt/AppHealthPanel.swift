import AppKit
import SwiftUI

/// The borderless, non-activating window behind the labelling prompt and the manual picker.
///
/// It never becomes main and becomes key only while `acceptsKeyboardFocus` is true: the prompt sets it after a
/// click inside, the picker from the start. Escape is handled by the owner's key monitor, so AppKit's own
/// `cancelOperation` (which would close a panel) does nothing here.
final class AppHealthPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var becameKey: (() -> Void)?
    var resignedKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        becameKey?()
    }

    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }

    override func cancelOperation(_ sender: Any?) {}

    /// The shared window setup: transparent, shadowed, kept on screen when DOKK is inactive, and on every Space
    /// like the dock popovers.
    static func make(level: NSWindow.Level) -> AppHealthPanel {
        let panel = AppHealthPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.title = String(localized: .appHealthTitle)
        return panel
    }
}

/// Hosts a panel's SwiftUI content and reports the pointer entering and leaving it.
///
/// The tracking area is `.activeAlways` because DOKK is usually not the active app while a prompt is up; the
/// default tracking modes would report nothing then.
final class AppHealthPanelContentView<Content: View>: NSView {
    let hosting: AppHealthHostingView<Content>
    var pointerChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    init(rootView: Content) {
        hosting = AppHealthHostingView(rootView: rootView)
        // Only the intrinsic size: the owner sizes the window from the content, so the hosting view must not add
        // required minimum or maximum constraints that fight it mid-resize.
        hosting.sizingOptions = [.intrinsicContentSize]
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(false) }
}

/// Accepts the first click, so a button in a panel of an inactive app works on the first click.
final class AppHealthHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The keys a focused labelling question understands: Tab and the arrows move between controls, Return and Space
/// activate the highlighted one, Escape closes it.
enum AppHealthLabelKeyboard {
    /// Handles `event` for `session`. Returns true when the key was consumed.
    static func handle(_ event: NSEvent, session: AppHealthLabelSession) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case KeyCode.escape:
            session.dismiss()
            return true
        case KeyCode.tab:
            session.moveHighlight(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        case KeyCode.left, KeyCode.up:
            session.moveHighlight(by: -1)
            return true
        case KeyCode.right, KeyCode.down:
            session.moveHighlight(by: 1)
            return true
        case KeyCode.returnKey, KeyCode.enter, KeyCode.space:
            return session.activateHighlighted()
        default:
            return false
        }
    }

    /// Virtual key codes from `HIToolbox/Events.h`.
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }
}
