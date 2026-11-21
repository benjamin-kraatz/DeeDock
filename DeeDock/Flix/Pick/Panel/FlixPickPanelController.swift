import AppKit
import SwiftUI

/// Flix Pick's window: a borderless non-activating panel that can never become key or main, so a
/// click in it leaves the other app frontmost and its picker focused.
private final class FlixPickWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click while DOKK is in the background, and only inside the body: a click on
/// the transparent shadow margin must not reach a row laid out under it (rows are laid out at the
/// open width and clipped only visually while the rail is closed).
private final class FlixPickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        let margin = FlixPickPlacement.shadowMargin
        guard bounds.insetBy(dx: margin, dy: margin).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Owns Flix Pick's panel window: where it sits beside the picker, following the picker, the
/// rail opening on hover, and the entrance and exit.
///
/// The window is the body plus a transparent shadow margin. Its frame always matches the body's
/// current size, so the panel never covers more than it shows: opening the rail first widens the
/// window (the edge next to the picker stays put) and then springs the body open inside it;
/// closing springs the body shut and only then narrows the window. With Reduce Motion the body
/// and the window change size at once and only the text fades. The timings are `FlixPickMotion`'s.
///
/// Never activates DOKK and never becomes key: `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`,
/// and a window class that refuses key. Floating level, on every Space and beside full-screen
/// apps, and not hidden when DOKK is inactive (it always is). Main actor.
@MainActor
final class FlixPickPanelController {
    private let window: FlixPickWindow
    private let state: FlixPickState
    private var generation = 0
    /// The picker's frame and its display's visible frame, in AppKit space.
    private var picker: CGRect = .zero
    private var visible: CGRect = .zero
    /// Whether the window is sized for the open rail.
    private var windowOpen = false
    private(set) var isVisible = false

    init<Content: View>(state: FlixPickState, content: Content) {
        self.state = state
        window = FlixPickWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.title = String(localized: .flixPickName)
        let hosting = FlixPickHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.contentView = hosting
    }

    /// Whether a screen point is over the panel's body.
    func contains(_ point: CGPoint) -> Bool { isVisible && body(open: state.isOpen).contains(point) }

    /// Shows the rail beside `picker` (AppKit space), closed.
    func show(beside picker: CGRect) {
        generation += 1
        let token = generation
        place(picker)
        state.side = FlixPickPlacement.side(picker: picker, visible: visible)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.isOpen = false
            state.isShown = false
        }
        windowOpen = false
        window.setFrame(FlixPickPlacement.window(around: body(open: false)), display: false)
        isVisible = true
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == token else { return }
            // The fade; the slide and scale take their own spring in `FlixPickEntrance`.
            withAnimation(FlixPickMotion.fadeIn) { self.state.isShown = true }
        }
    }

    /// Follows the picker as it moves or resizes. The side stays as chosen at show.
    func follow(_ picker: CGRect) {
        guard isVisible, picker != self.picker else { return }
        place(picker)
        window.setFrame(FlixPickPlacement.window(around: body(open: windowOpen)), display: true)
    }

    /// The number of rows changed.
    func refreshSize() {
        guard isVisible else { return }
        window.setFrame(FlixPickPlacement.window(around: body(open: windowOpen)), display: true)
    }

    /// Opens or closes the rail.
    func setOpen(_ open: Bool) {
        guard isVisible, open != state.isOpen else { return }
        if state.reduceMotion {
            // No transaction animation, so the width changes at once; the text still fades, as its
            // reveal carries its own animation.
            if open { resizeWindow(open: true) }
            state.isOpen = open
            if !open { resizeWindow(open: false) }
        } else if open {
            resizeWindow(open: true)
            withAnimation(FlixPickMotion.open) { state.isOpen = true }
        } else {
            let token = generation
            withAnimation(FlixPickMotion.close) { state.isOpen = false } completion: { [weak self] in
                guard let self, generation == token, isVisible, !state.isOpen else { return }
                resizeWindow(open: false)
            }
        }
    }

    /// Sizes the window for the open or the closed rail; the edge next to the picker stays put.
    private func resizeWindow(open: Bool) {
        windowOpen = open
        window.setFrame(FlixPickPlacement.window(around: body(open: open)), display: true)
    }

    /// Fades away and orders out.
    func hide(animated: Bool = true) {
        guard isVisible else { return }
        generation += 1
        let token = generation
        isVisible = false
        let finish = { [weak self] in
            guard let self, generation == token else { return }
            window.orderOut(nil)
            state.isOpen = false
            windowOpen = false
        }
        guard animated else {
            state.isShown = false
            finish()
            return
        }
        withAnimation(FlixPickMotion.leave) { state.isShown = false } completion: { finish() }
    }

    /// Hides at once and releases the content. The controller must not be used after.
    func stop() {
        hide(animated: false)
        window.contentView = nil
    }

    private func place(_ picker: CGRect) {
        self.picker = picker
        let center = CGPoint(x: picker.midX, y: picker.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(picker) } ?? NSScreen.main
        visible = screen?.visibleFrame ?? picker
    }

    private func body(open: Bool) -> CGRect {
        FlixPickPlacement.body(picker: picker, visible: visible, rows: state.rows.count, open: open, side: state.side)
    }
}
