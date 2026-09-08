import AppKit
import SwiftUI

/// Native destination receives the existing drag, without loading providers again or taking focus.
/// Ordinary pointer events pass through to the SwiftUI card beneath it.
struct WindowPeekFileDropView: NSViewRepresentable {
    let update: (NSDraggingInfo) -> Bool
    let receive: (NSDraggingInfo) -> Bool
    let exit: () -> Void
    let ended: () -> Void

    func makeNSView(context: Context) -> DestinationView { DestinationView() }
    func updateNSView(_ view: DestinationView, context: Context) {
        view.update = update; view.receive = receive; view.exit = exit; view.ended = ended
    }
    static func dismantleNSView(_ view: DestinationView, coordinator: ()) {
        view.unregisterDraggedTypes()
        view.update = nil; view.receive = nil; view.exit = nil; view.ended = nil
    }

    final class DestinationView: NSView {
        var update: ((NSDraggingInfo) -> Bool)?
        var receive: ((NSDraggingInfo) -> Bool)?
        var exit: (() -> Void)?
        var ended: (() -> Void)?
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSEvent.pressedMouseButtons & 1 != 0,
                  NSApp.currentEvent?.type != .leftMouseDown else { return nil }
            return super.hitTest(point)
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            update?(sender) == true ? .copy : []
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { update?(sender) == true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { receive?(sender) ?? false }
        override func draggingExited(_ sender: NSDraggingInfo?) { exit?() }
        override func draggingEnded(_ sender: NSDraggingInfo) { ended?() }
    }
}
