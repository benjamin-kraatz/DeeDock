import AppKit
import SwiftUI

/// Native file drag source that preserves click behavior and reports accepted copy or move operations.
struct FolderStackDragSourceView: NSViewRepresentable {
    let entry: FolderStackEntry
    let open: () -> Void
    let completed: (Bool) -> Void
    var lease: () -> FolderResourceAccess? = { nil }
    var select: () -> Void = {}
    var navigate: () -> Void = {}
    var receive: (NSDraggingInfo) -> Bool = { _ in false }
    var acceptsDrop: () -> Bool = { false }

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.entry = entry; view.openEntry = open; view.completed = completed
        view.lease = lease
        view.select = select; view.navigate = navigate; view.receive = receive; view.acceptsDrop = acceptsDrop
        if entry.reference.isFolder { view.registerForDraggedTypes([.fileURL]) }
        else { view.unregisterDraggedTypes() }
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView, NSDraggingSource, NSSpringLoadingDestination {
        var entry: FolderStackEntry?
        var openEntry: (() -> Void)?
        var completed: ((Bool) -> Void)?
        var lease: (() -> FolderResourceAccess?)?
        private var dragLease: FolderResourceAccess?
        /// AppKit does not own the source lease after a different stack removes this row.
        private var retained: SourceView?
        private var dragCompleted: ((Bool) -> Void)?
        private var highlighted = false
        var select: (() -> Void)?
        var navigate: (() -> Void)?
        var receive: ((NSDraggingInfo) -> Bool)?
        var acceptsDrop: (() -> Bool)?
        private var stopped = false

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if highlighted {
                NSColor.controlAccentColor.setStroke()
                let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
                outline.lineWidth = 2
                outline.stroke()
            }
        }
        func springLoadingHighlightChanged(_ info: NSDraggingInfo) {
            highlighted = info.springLoadingHighlight != .none
            needsDisplay = true
        }
        func springLoadingExited(_ info: NSDraggingInfo) {
            highlighted = false
            needsDisplay = true
        }
        override func draggingExited(_ sender: NSDraggingInfo?) {
            highlighted = false
            needsDisplay = true
        }
        override func draggingEnded(_ sender: NSDraggingInfo) {
            highlighted = false
            needsDisplay = true
        }
        // Let SwiftUI own secondary clicks and its context menu.
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent,
               event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) { return nil }
            return super.hitTest(point)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard !stopped, entry?.reference.isFolder == true, acceptsDrop?() == true,
                  FolderFileDrop.urls(sender) != nil else { return [] }
            return .copy
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !draggingEntered(sender).isEmpty }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { receive?(sender) ?? false }
        func springLoadingEntered(_ info: NSDraggingInfo) -> NSSpringLoadingOptions {
            draggingEntered(info).isEmpty ? [] : .enabled
        }
        func springLoadingUpdated(_ info: NSDraggingInfo) -> NSSpringLoadingOptions { springLoadingEntered(info) }
        func springLoadingActivated(_ activated: Bool, draggingInfo: NSDraggingInfo) {
            if activated, !draggingEntered(draggingInfo).isEmpty { navigate?() }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func mouseDown(with event: NSEvent) {
            guard let window, let entry else { return }
            select?()
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                if next.type == .leftMouseUp {
                    if event.clickCount >= 2, bounds.contains(convert(next.locationInWindow, from: nil)) { openEntry?() }
                    return
                }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    let pasteboard = NSPasteboardItem()
                    pasteboard.setString(entry.reference.url.absoluteString, forType: .fileURL)
                    let item = NSDraggingItem(pasteboardWriter: pasteboard)
                    let dimension = min(bounds.width, bounds.height)
                    item.setDraggingFrame(CGRect(x: bounds.midX - dimension / 2, y: bounds.midY - dimension / 2,
                                                 width: dimension, height: dimension), contents: entry.icon)
                    dragLease = lease?()
                    dragCompleted = completed
                    retained = self
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
            dragCompleted?(!operation.intersection([.copy, .move]).isEmpty)
            dragCompleted = nil
            dragLease = nil
            retained = nil
        }
        func stop() {
            stopped = true; unregisterDraggedTypes()
            entry = nil; openEntry = nil; completed = nil
            lease = nil; select = nil; navigate = nil; receive = nil; acceptsDrop = nil
        }
    }
}
