import AppKit
import SwiftUI

/// Native mouse handling behind a row, a Fits row, or a thread card.
///
/// Selection happens on press, as in a Finder list, so a drag that starts on an already selected
/// row carries the whole selection; a press inside a multiple selection collapses it only on
/// mouse-up without a drag. Double-click opens. A right-click or Control-click shows the context
/// menu the closure builds, as an `NSMenu`. It sits behind the row's content, which passes the
/// pointer through except on its own buttons, so it also reports hover (a tracking area), which
/// only highlights.
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

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
        override func mouseEntered(with event: NSEvent) { configuration?.hover(true) }
        override func mouseExited(with event: NSEvent) { configuration?.hover(false) }

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

        func stop() {
            stopped = true
            configuration = nil
        }
    }
}
