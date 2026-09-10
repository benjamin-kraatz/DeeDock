import AppKit
import SwiftUI

/// One parked pin or stack. Clicking opens it; dragging starts the shared dock session.
struct DockMagneticAttachmentView: View {
    let icon: NSImage
    let size: CGFloat
    let name: String
    let available: Bool
    /// Folder stacks keep the same badge they show on the linear dock.
    var showsStackBadge: Bool = false
    let open: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    var body: some View {
        ZStack {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .opacity(available ? 1 : 0.45)
            if showsStackBadge {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: max(10, size * 0.22), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.tint, in: Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: -2, y: -2)
                    .accessibilityHidden(true)
            }
            DockMagneticDragSourceView(enabled: true, primaryAction: open, begin: begin, tracking: tracking)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

/// Same click-versus-drag threshold as dock tiles, without making the panel key.
private struct DockMagneticDragSourceView: NSViewRepresentable {
    let enabled: Bool
    let primaryAction: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.enabled = enabled
        view.primaryAction = primaryAction
        view.begin = begin
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var enabled = true
        var primaryAction: (() -> Void)?
        var begin: ((NSView, NSEvent) -> Void)?
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
            guard let window else { return }
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
                    begin?(self, next)
                    return
                }
            }
        }

        func stop() {
            tracking?(false)
            tracking = nil
            stopped = true
            begin = nil
            primaryAction = nil
        }
    }
}

#if DEBUG
#Preview("Parked pin") {
    DockMagneticAttachmentView(
        icon: NSImage(size: NSSize(width: 128, height: 128)),
        size: 48,
        name: "Preview",
        available: true,
        open: {},
        begin: { _, _ in },
        tracking: { _ in }
    )
    .padding()
    .background(Color.black.opacity(0.25))
}

#Preview("Parked folder stack") {
    DockMagneticAttachmentView(
        icon: NSImage(size: NSSize(width: 128, height: 128)),
        size: 48,
        name: "Preview",
        available: true,
        showsStackBadge: true,
        open: {},
        begin: { _, _ in },
        tracking: { _ in }
    )
    .padding()
    .background(Color.black.opacity(0.25))
}
#endif
