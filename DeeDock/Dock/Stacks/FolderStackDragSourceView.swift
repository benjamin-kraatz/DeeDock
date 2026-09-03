import AppKit
import SwiftUI

/// Native file drag source that preserves click behavior and reports accepted copy or move operations.
struct FolderStackDragSourceView: NSViewRepresentable {
    let entry: FolderStackEntry
    let open: () -> Void
    let completed: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.entry = entry; view.openEntry = open; view.completed = completed
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView, NSDraggingSource {
        var entry: FolderStackEntry?
        var openEntry: (() -> Void)?
        var completed: ((Bool) -> Void)?
        private var stopped = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func mouseDown(with event: NSEvent) {
            guard let window, let entry else { return }
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { openEntry?() }
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    let pasteboard = NSPasteboardItem()
                    pasteboard.setString(entry.reference.url.absoluteString, forType: .fileURL)
                    let item = NSDraggingItem(pasteboardWriter: pasteboard)
                    let dimension = min(bounds.width, bounds.height)
                    item.setDraggingFrame(CGRect(x: bounds.midX - dimension / 2, y: bounds.midY - dimension / 2,
                                                 width: dimension, height: dimension), contents: entry.icon)
                    let session = beginDraggingSession(with: [item], event: next, source: self)
                    session.animatesToStartingPositionsOnCancelOrFail = true
                    return
                }
            }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .move]
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            completed?(!operation.intersection([.copy, .move]).isEmpty)
        }
        func stop() { stopped = true; entry = nil; openEntry = nil; completed = nil }
    }
}
