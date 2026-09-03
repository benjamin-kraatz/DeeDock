import AppKit
import SwiftUI

/// Native mouse tracking for a pinned folder, matching application click and drag thresholds.
struct DockFolderDragSourceView: NSViewRepresentable {
    let item: FolderDockItem
    let primaryAction: () -> Void
    let begin: (FolderDockItem, NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.item = item; view.primaryAction = primaryAction; view.begin = begin; view.tracking = tracking
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var item: FolderDockItem?
        var primaryAction: (() -> Void)?
        var begin: ((FolderDockItem, NSView, NSEvent) -> Void)?
        var tracking: ((Bool) -> Void)?
        private var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window, let item else { return }
            tracking?(true)
            defer { tracking?(false) }
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { primaryAction?() }
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    begin?(item, self, next)
                    return
                }
            }
        }
        func stop() { stopped = true; tracking?(false); tracking = nil; item = nil; primaryAction = nil; begin = nil }
    }
}
