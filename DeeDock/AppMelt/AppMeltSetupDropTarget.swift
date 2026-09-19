import AppKit
import SwiftUI

/// Accepts only a live DDock application drag token, never arbitrary serialized app references.
struct AppMeltSetupDropTarget: NSViewRepresentable {
    let state: AppMeltSetupState
    let index: Int
    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([DockDragCoordinator.pasteboardType])
        return view
    }
    func updateNSView(_ view: DropView, context: Context) { view.state = state; view.index = index }
    static func dismantleNSView(_ view: DropView, coordinator: ()) { view.unregisterDraggedTypes(); view.state = nil }

    final class DropView: NSView {
        weak var state: AppMeltSetupState?
        var index = 1
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let type = NSApp.currentEvent?.type, type == .leftMouseDown || type == .rightMouseDown { return nil }
            return super.hitTest(point)
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { operation(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { operation(sender) }
        private func operation(_ sender: NSDraggingInfo) -> NSDragOperation {
            state?.canAcceptDockApplication(sender.draggingPasteboard, at: index) == true ? .copy : []
        }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !operation(sender).isEmpty }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            state?.acceptDockApplication(sender.draggingPasteboard, at: index) == true
        }
    }
}
