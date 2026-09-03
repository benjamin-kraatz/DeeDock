import AppKit
import SwiftUI

/// Native mouse tracking distinguishes clicks from drags without making the nonactivating panel key.
struct DockDragSourceView: NSViewRepresentable {
    let item: DockItem
    let enabled: Bool
    let open: () -> Void
    let begin: (DockItem, NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.item = item; view.enabled = enabled; view.open = open; view.begin = begin; view.tracking = tracking
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var item: DockItem?
        var enabled = true
        var open: (() -> Void)?
        var begin: ((DockItem, NSView, NSEvent) -> Void)?
        var tracking: ((Bool) -> Void)?
        private var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, let event = NSApp.currentEvent,
                  event.type == .leftMouseDown, !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window, let item else { return }
            tracking?(true)
            defer { tracking?(false) }
            let origin = event.locationInWindow
            // AppKit's tracking loop retains mouse delivery outside the nonactivating panel.
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                                        until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { open?() }
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    begin?(item, self, next)
                    return
                }
            }
        }
        func stop() { tracking?(false); tracking = nil; stopped = true; begin = nil; open = nil; item = nil }
    }
}
