import AppKit
import SwiftUI

/// Shows one labelling prompt next to the app's dock tile without taking focus.
///
/// The panel is ordered front with `orderFrontRegardless()`: DOKK is never activated and the panel is never made
/// key on show. It becomes key only after a click inside it, which is what lets Tab, the arrows, Return, Space, and
/// Escape reach it. There is no outside-click dismissal: an ambient question must survive the person working
/// elsewhere, and it ends through its own buttons, Escape, or the session's timers. It is not registered with
/// `DockPopoverPresenter`, so it neither closes nor is closed by folder stacks and other dock popovers.
///
/// Owns one local event monitor and one screen-parameters observer, both removed in `close()`.
@MainActor
final class AppHealthPromptPanelController: AppHealthPromptPresenting {
    private let panel = AppHealthPanel.make(level: .popUpMenu)
    private let session: AppHealthLabelSession
    private let reanchor: @MainActor () -> AppHealthAnchor?
    private var anchor: AppHealthAnchor
    private var size: CGSize
    private var content: AppHealthPanelContentView<AppHealthPromptView>?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var pointerInside = false
    private var closed = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// - Parameter reanchor: Finds the anchor again after the display arrangement changed.
    init(session: AppHealthLabelSession, anchor: AppHealthAnchor,
         reanchor: @escaping @MainActor () -> AppHealthAnchor?) {
        self.session = session
        self.anchor = anchor
        self.reanchor = reanchor
        size = CGSize(width: AppHealthPromptView.width, height: 160)
        let content = AppHealthPanelContentView(rootView: AppHealthPromptView(
            session: session, attachedEdge: anchor.edge
        ) { [weak self] size in
            // Reported during SwiftUI layout; resizing the window from inside that pass would re-enter it.
            DispatchQueue.main.async { self?.contentSizeChanged(size) }
        })
        let fitting = content.hosting.fittingSize
        if fitting.width > 0, fitting.height > 0 { size = fitting }
        content.pointerChanged = { [weak self] inside in
            self?.pointerInside = inside
            self?.updateEngagement()
        }
        self.content = content
        panel.contentView = content
        panel.becameKey = { [weak self] in self?.keyStateChanged() }
        panel.resignedKey = { [weak self] in self?.keyStateChanged() }
        panel.setFrame(AppHealthPromptPlacement.frame(size: size, anchor: anchor), display: false)
    }

    /// Orders the prompt in: the window rises a little from the dock edge while it fades in, and the card inside
    /// grows from that edge with its own spring. Reduce Motion fades alone.
    func show() {
        guard !closed else { return }
        installMonitor()
        observeScreens()
        let frame = AppHealthPromptPlacement.frame(size: size, anchor: anchor)
        panel.alphaValue = 0
        if reduceMotion {
            panel.setFrame(frame, display: false)
        } else {
            panel.setFrame(DockPopoverGeometry.dismissedFrame(from: frame, edge: anchor.edge ?? .bottom), display: false)
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    /// Fades the prompt out, settling back toward the dock edge it rose from; Reduce Motion fades alone.
    func close() {
        guard !closed else { return }
        closed = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        content?.pointerChanged = nil
        panel.becameKey = nil
        panel.resignedKey = nil
        let panel = panel
        let destination = DockPopoverGeometry.dismissedFrame(from: panel.frame, edge: anchor.edge ?? .bottom)
        let reduceMotion = reduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !reduceMotion { panel.animator().setFrame(destination, display: true) }
        } completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    // MARK: - Input

    private func installMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self, !closed, event.window === panel else { return event }
            if event.type == .keyDown {
                return AppHealthLabelKeyboard.handle(event, session: session) ? nil : event
            }
            // Only a deliberate click inside grants keyboard focus; showing the prompt or hovering never does.
            // The panel is non-activating, so becoming key leaves the person's app active.
            if !panel.acceptsKeyboardFocus {
                panel.acceptsKeyboardFocus = true
                panel.makeKey()
            }
            return event
        }
    }

    private func keyStateChanged() {
        guard !closed else { return }
        let isKey = panel.isKeyWindow
        // Once focus moves elsewhere, the next keyboard focus again needs a click inside.
        if !isKey { panel.acceptsKeyboardFocus = false }
        session.setKeyboardActive(isKey)
        updateEngagement()
    }

    /// The expiry pauses while the pointer is over the prompt or the prompt has keyboard focus.
    private func updateEngagement() {
        guard !closed else { return }
        session.setEngaged(pointerInside || panel.isKeyWindow)
    }

    // MARK: - Placement

    /// Follows a phase change's new height. The window eases to the new frame while the card inside, already
    /// laid out at the new size and held against the dock edge, is uncovered; Reduce Motion jumps.
    private func contentSizeChanged(_ newSize: CGSize) {
        guard !closed, newSize.width > 0, newSize.height > 0,
              abs(newSize.width - size.width) > 0.5 || abs(newSize.height - size.height) > 0.5 else { return }
        size = newSize
        let frame = AppHealthPromptPlacement.frame(size: size, anchor: anchor)
        guard !reduceMotion, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Follows the anchor when displays are added, removed, rearranged, or change resolution.
    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    private func reposition() {
        guard !closed else { return }
        if let next = reanchor() { anchor = next }
        panel.setFrame(AppHealthPromptPlacement.frame(size: size, anchor: anchor), display: true)
    }
}
