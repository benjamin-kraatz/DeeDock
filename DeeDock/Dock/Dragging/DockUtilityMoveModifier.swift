import AppKit
import SwiftUI

/// Keeps built-in tile movement separate from file and pin drags.
struct DockUtilityMoveModifier: ViewModifier {
    let slot: DockRenderSlot
    let interaction: DockInteraction

    func body(content: Content) -> some View {
        if let id = slot.movableUtilityID {
            content
                .overlay {
                    DockUtilityMoveSource(
                        optionDragsFiles: slot.shelf != nil,
                        click: {
                            if let folder = slot.folder { interaction.openFolder?(folder, false) }
                            else if slot.shelf != nil { interaction.openShelf?() }
                            else { interaction.openSessionCapsules?() }
                        },
                        begin: { view, event in interaction.beginUtilityDrag?(slot, view, event) },
                        tracking: { interaction.sourceTrackingChanged?($0) }
                    )
                }
                .opacity(slot.folder == nil && interaction.dragSourceID == id ? 0.3 : 1)
                .accessibilityActions {
                    if interaction.canMoveUtility?(id, -1) == true {
                        Button {
                            interaction.moveUtility?(id, -1)
                        } label: {
                            Text(interaction.layout.edge.isVertical ? .actionMoveUp : .actionMoveLeft)
                        }
                    }
                    if interaction.canMoveUtility?(id, 1) == true {
                        Button {
                            interaction.moveUtility?(id, 1)
                        } label: {
                            Text(interaction.layout.edge.isVertical ? .actionMoveDown : .actionMoveRight)
                        }
                    }
                }
        } else {
            content
        }
    }
}

/// Distinguishes clicks from native utility drags without activating the dock panel.
private struct DockUtilityMoveSource: NSViewRepresentable {
    let optionDragsFiles: Bool
    let click: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.configuration = self
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) {
        view.stopped = true
        view.configuration = nil
    }

    final class SourceView: NSView {
        var configuration: DockUtilityMoveSource?
        var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control),
                  !(configuration?.optionDragsFiles == true && event.modifierFlags.contains(.option)) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window, let configuration else { return }
            configuration.tracking(true)
            defer { configuration.tracking(false) }
            // Screen points stay stable if the panel moves while the mouse is held.
            let origin = window.convertPoint(toScreen: event.locationInWindow)
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                let point = window.convertPoint(toScreen: next.locationInWindow)
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { configuration.click() }
                    return
                }
                if hypot(point.x - origin.x, point.y - origin.y) >= DockDragGeometry.startDistance {
                    configuration.begin(self, next)
                    return
                }
            }
        }
    }
}
