import AppKit
import SwiftUI

/// Borderless, non-activating panel: clicks and typing never activate the lab, so the target app
/// stays frontmost and keeps its selection.
final class CompanionPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 140, height: 60),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

final class CompanionHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHover?(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHover?(false) }
}

/// Transparent sheet over the target window during selection mode. It swallows the drag so the
/// app underneath never sees it — the "guard" that keeps normal dragging in the app untouched.
final class SelectionView: NSView {
    var onRegion: ((CGRect) -> Void)?   // window-local, top-left points
    var onWhole: (() -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.12).setFill()
        shape.fill()
        guard let r = selection else { return }
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        let outline = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        outline.fill()
        NSColor.controlAccentColor.setStroke()
        outline.lineWidth = 2
        outline.setLineDash([7, 4], count: 2, phase: 0)
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); current = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { current = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; current = nil; needsDisplay = true }
        guard let r = selection, r.width > 12, r.height > 12 else { onWhole?(); return }
        onRegion?(CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height))
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 49: onWhole?()
        default: super.keyDown(with: event)
        }
    }
}
