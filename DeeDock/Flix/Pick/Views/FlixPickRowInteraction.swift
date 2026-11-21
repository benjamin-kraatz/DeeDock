import AppKit
import SwiftUI

/// Native mouse handling behind a Flix Pick row.
///
/// A click (on release, without a drag) selects; ⌥ held at the press makes it an ⌥-click; the
/// second press of a double-click reports ``doubleClick`` at once. A press that moves past the
/// drag distance starts a drag of the row instead. Takes the first click while DOKK is in the
/// background, and never takes focus: the panel cannot become key.
struct FlixPickRowInteraction: NSViewRepresentable {
    var press: (Bool) -> Void
    var click: (_ option: Bool) -> Void
    var doubleClick: () -> Void
    var begin: (NSView, NSEvent) -> Void
    var hover: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var configuration: FlixPickRowInteraction?
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
            if event.clickCount >= 2 {
                configuration.doubleClick()
                return
            }
            let option = event.modifierFlags.contains(.option)
            configuration.press(true)
            defer { configuration.press(false) }
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                                       until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .leftMouseUp {
                    configuration.click(option)
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    configuration.begin(self, next)
                    return
                }
            }
        }

        func stop() {
            stopped = true
            configuration = nil
        }
    }
}

/// Reports the pointer entering and leaving the panel body, whether or not DOKK is active.
struct FlixPickHoverTracker: NSViewRepresentable {
    var hover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) { view.hover = hover }
    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.hover = nil }

    final class TrackingView: NSView {
        var hover: ((Bool) -> Void)?

        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
        override func mouseEntered(with event: NSEvent) { hover?(true) }
        override func mouseExited(with event: NSEvent) { hover?(false) }
    }
}
