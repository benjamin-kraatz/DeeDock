import AppKit
import SwiftUI

/// Owns the floating chrome for pins and stacks parked by magnetism.
@MainActor
final class DockMagneticAttachmentController {
    private var panels: [String: NSPanel] = [:]
    private var hidden: Set<String> = []

    /// Rebuilds panels to match `placements`. Keys are `displayID/pinID`.
    func sync(_ attachments: [DockMagneticAttachment]) {
        let wanted = Set(attachments.map(\.id))
        for id in panels.keys where !wanted.contains(id) {
            panels[id]?.close()
            panels[id] = nil
        }
        for attachment in attachments {
            if hidden.contains(attachment.id) {
                panels[attachment.id]?.orderOut(nil)
                continue
            }
            let panel = preparedPanel(id: attachment.id)
            panel.setFrame(attachment.frame, display: true)
            panel.contentView = NSHostingView(rootView: DockMagneticAttachmentView(
                icon: attachment.icon,
                size: min(attachment.frame.width, attachment.frame.height),
                name: attachment.name,
                available: attachment.available,
                showsStackBadge: attachment.showsStackBadge,
                open: attachment.open,
                begin: attachment.begin,
                tracking: attachment.tracking
            ))
            panel.orderFrontRegardless()
        }
    }

    /// Hides one attachment while its native drag image is in flight.
    func hideDuringDrag(displayID: String, pinID: String) {
        let id = DockMagneticAttachment.id(displayID: displayID, pinID: pinID)
        hidden.insert(id)
        panels[id]?.orderOut(nil)
    }

    func revealAfterDrag() {
        hidden.removeAll()
    }

    func stop() {
        hidden.removeAll()
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }

    private func preparedPanel(id: String) -> NSPanel {
        if let panel = panels[id] { return panel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panels[id] = panel
        return panel
    }
}

/// Everything one parked tile needs to draw and interact.
struct DockMagneticAttachment: Identifiable {
    let displayID: String
    let pinID: String
    let frame: CGRect
    let icon: NSImage
    let name: String
    let available: Bool
    let showsStackBadge: Bool
    let open: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    var id: String { Self.id(displayID: displayID, pinID: pinID) }

    static func id(displayID: String, pinID: String) -> String { "\(displayID)|\(pinID)" }
}
