import AppKit
import SwiftUI

/// Tracks a local tear-off gesture without exporting window metadata to another application.
/// Screen coordinates remain stable across display origins and while Peek changes its layout.
struct WindowPeekPortalDragSource: NSViewRepresentable {
    let card: WindowPeekCard
    let click: () -> Void
    let tracking: (Bool) -> Void
    let drop: (CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) {
        view.stopped = true
        view.ghost?.orderOut(nil)
        view.configuration = nil
    }

    final class SourceView: NSView {
        var configuration: WindowPeekPortalDragSource?
        var stopped = false
        var ghost: NSPanel?
        private var ghostMode: (frozen: Bool, cancelled: Bool)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window, let configuration else { return }
            let origin = window.convertPoint(toScreen: event.locationInWindow)
            var dragging = false
            configuration.tracking(true)
            defer {
                ghost?.orderOut(nil)
                ghost = nil
                ghostMode = nil
                configuration.tracking(false)
            }
            // Use the same event-tracking loop as dock tile drags. Never activate the source app.
            while !stopped {
                guard let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .flagsChanged],
                    until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true
                ) else { continue }
                if next.type == .keyDown {
                    if next.keyCode == 53 { return }
                    continue
                }
                let point = NSEvent.mouseLocation
                if !dragging, hypot(point.x - origin.x, point.y - origin.y) >= DockDragGeometry.startDistance {
                    dragging = true
                }
                let frozen = next.modifierFlags.contains(.option)
                if next.type == .leftMouseUp {
                    if dragging {
                        if !window.frame.contains(point) { configuration.drop(point, frozen) }
                    } else if bounds.contains(convert(next.locationInWindow, from: nil)) {
                        configuration.click()
                    }
                    return
                }
                if dragging { updateGhost(card: configuration.card, point: point, frozen: frozen,
                                          cancelled: window.frame.contains(point)) }
            }
        }

        private func updateGhost(card: WindowPeekCard, point: CGPoint, frozen: Bool, cancelled: Bool) {
            if ghost == nil {
                let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 240, height: 180),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.level = .popUpMenu
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                ghost = panel
            }
            // Pointer motion only moves the panel. Rebuild its content when the proposed action changes.
            if ghostMode?.frozen != frozen || ghostMode?.cancelled != cancelled {
                ghost?.contentView = NSHostingView(rootView: WindowPeekPortalDragPreview(
                    image: card.thumbnail, frozen: frozen, cancelled: cancelled))
                ghostMode = (frozen, cancelled)
            }
            ghost?.setFrameOrigin(CGPoint(x: point.x + 16, y: point.y - 180))
            ghost?.orderFrontRegardless()
        }
    }
}

private struct WindowPeekPortalDragPreview: View {
    let image: CGImage?
    let frozen: Bool
    let cancelled: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
            } else {
                Image(systemName: "macwindow").font(.largeTitle).frame(maxHeight: .infinity)
            }
            Label(cancelled ? .portalDragCancel : (frozen ? .portalPinFrozen : .portalPin),
                  systemImage: cancelled ? "arrow.uturn.backward" : (frozen ? "snowflake" : "pin"))
                .font(.caption.weight(.semibold))
            Text(.portalDragModifier).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 240, height: 180)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}
