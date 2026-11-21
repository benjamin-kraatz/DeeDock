import AppKit
import SwiftUI

/// Native mouse handling behind a row, a Fits row, or a thread card.
///
/// Selection happens on press, as in a Finder list, so a drag that starts on an already selected
/// row carries the whole selection; a press inside a multiple selection collapses it only on
/// mouse-up without a drag. Double-click opens. A right-click or Control-click shows the context
/// menu the closure builds, as an `NSMenu`. It sits behind the row's content, which passes the
/// pointer through except on its own buttons, so it also reports hover, which only highlights:
/// a tracking area plus a check against the pointer's real position while the list scrolls.
struct FlixRowInteraction: NSViewRepresentable {
    var press: (_ command: Bool, _ shift: Bool) -> Void
    var click: (_ command: Bool, _ shift: Bool) -> Void
    var open: () -> Void
    var begin: (NSView, NSEvent) -> Void
    var menu: () -> NSMenu?
    var hover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var configuration: FlixRowInteraction?
        private var stopped = false
        private var isHovered = false
        private var trackingArea: NSTrackingArea?
        /// The list's clip view, observed for scroll-driven hover updates. Weak: the scroll view
        /// outlives the row, and `detachScrollObserver()` removes the observer by this reference.
        private weak var observedClipView: NSClipView?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }

        // MARK: Hover
        //
        // Tracking-area enter and exit alone leave rows highlighted when the list scrolls under a
        // pointer that stays put: AppKit rebuilds tracking areas as the visible rect changes and
        // sends no `mouseExited` for an area removed while it contained the pointer, and scrolling
        // sends no mouse-moved event. So hover is also reconciled against the pointer's real
        // position on each tracking-area rebuild and each scroll step, as Hub Files does
        // (`HubFilesInteractionView`, DEE-132).

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            reconcileHover()
            installTrackingArea()
        }

        /// Replaces the tracking area. While hovered, the new area assumes the pointer is inside,
        /// so the next exit is still delivered.
        private func installTrackingArea() {
            if let trackingArea { removeTrackingArea(trackingArea) }
            var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            if isHovered { options.insert(.assumeInside) }
            let area = NSTrackingArea(rect: .zero, options: options, owner: self)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { setHovered(true) }
        override func mouseExited(with event: NSEvent) { setHovered(false) }

        @discardableResult
        private func setHovered(_ hovered: Bool) -> Bool {
            guard hovered != isHovered, !stopped else { return false }
            isHovered = hovered
            configuration?.hover(hovered)
            return true
        }

        /// Sets hover from where the pointer is. Runs for every visible row on each scroll step, so
        /// the cheap geometry test comes first; only the row under the pointer asks the window
        /// server whether the panel is frontmost there. While a mouse button is held (a drag, a
        /// press) it only clears hover, as the tracking area would.
        @discardableResult
        private func reconcileHover() -> Bool {
            guard !stopped, let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return setHovered(false) }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard bounds.contains(point), visibleRect.contains(point) else { return setHovered(false) }
            guard NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
            else { return setHovered(false) }
            guard NSEvent.pressedMouseButtons == 0 else { return false }
            return setHovered(true)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachScrollObserver()
            if window == nil { reconcileHover() }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachScrollObserver()
        }

        /// Observes the enclosing clip view's bounds, which change on every scroll step.
        private func attachScrollObserver() {
            let clipView = stopped || window == nil ? nil : enclosingScrollView?.contentView
            guard clipView !== observedClipView else { return }
            detachScrollObserver()
            guard let clipView else { return }
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewBoundsDidChange(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: clipView)
            observedClipView = clipView
        }

        private func detachScrollObserver() {
            guard let observedClipView else { return }
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
            self.observedClipView = nil
        }

        /// The list scrolled under the pointer. When hover changes, the tracking area is rebuilt
        /// so its inside assumption matches.
        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            if reconcileHover() { installTrackingArea() }
        }

        // MARK: Clicks

        override func mouseDown(with event: NSEvent) {
            guard let window, let configuration else { return }
            if event.modifierFlags.contains(.control) { showMenu(event); return }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if event.clickCount >= 2, !command, !shift { configuration.open(); return }
            configuration.press(command, shift)
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                                       until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown {
                    if next.keyCode == 53 { return }
                    continue
                }
                if next.type == .leftMouseUp {
                    configuration.click(command, shift)
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    configuration.begin(self, next)
                    return
                }
            }
        }

        override func rightMouseDown(with event: NSEvent) { showMenu(event) }

        private func showMenu(_ event: NSEvent) {
            guard let configuration else { return }
            configuration.press(false, false)
            guard let menu = configuration.menu() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        /// Ends the row when SwiftUI dismantles it: reports a final hover exit, stops observing
        /// scrolling, and drops the callbacks.
        func stop() {
            detachScrollObserver()
            if isHovered { configuration?.hover(false) }
            isHovered = false
            stopped = true
            configuration = nil
        }
    }
}
