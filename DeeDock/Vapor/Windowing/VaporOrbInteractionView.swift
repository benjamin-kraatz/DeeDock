import AppKit

/// The orb window's content view: click, drag to move, right-click, hover and file drops.
///
/// Only the sphere itself is interactive: `hitTest` returns nil outside the orb's circle (plus
/// a few points of slop), and the transparent canvas around it lets clicks fall through to the
/// window below. Mouse events reach this view instead of the SwiftUI subview because hit-testing
/// returns `self`; the SwiftUI view still provides the accessibility element.
final class VaporOrbInteractionView: VaporDropView {
    /// A press that moved less than this is a click.
    static let dragThreshold: CGFloat = 3

    var clicked: (() -> Void)?
    /// The orb is being moved: its new centre in global coordinates and the event timestamp.
    var moved: ((CGPoint, TimeInterval) -> Void)?
    /// The move ended with the orb centred at this global point.
    var moveEnded: ((CGPoint) -> Void)?
    /// Builds the context menu for a right-click.
    var makeMenu: (() -> NSMenu)?
    var hoverChanged: ((Bool) -> Void)?

    private var pressLocation: CGPoint?
    private var pressOrigin: CGPoint?
    private var isMoving = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    private var orbCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func isInsideOrb(_ point: CGPoint) -> Bool {
        hypot(point.x - orbCenter.x, point.y - orbCenter.y) <= VaporGeometry.orbDiameter / 2 + 4
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return isInsideOrb(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressLocation = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin
        isMoving = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressLocation, let pressOrigin, let window else { return }
        let pointer = NSEvent.mouseLocation
        let delta = CGSize(width: pointer.x - pressLocation.x, height: pointer.y - pressLocation.y)
        if !isMoving, hypot(delta.width, delta.height) < Self.dragThreshold { return }
        isMoving = true
        window.setFrameOrigin(CGPoint(x: pressOrigin.x + delta.width, y: pressOrigin.y + delta.height))
        moved?(CGPoint(x: window.frame.midX, y: window.frame.midY), event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressLocation = nil
            pressOrigin = nil
            isMoving = false
        }
        guard pressLocation != nil else { return }
        if isMoving, let window {
            moveEnded?(CGPoint(x: window.frame.midX, y: window.frame.midY))
        } else {
            clicked?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }

    override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false
        hoverChanged?(false)
    }

    private func updateHover(_ event: NSEvent) {
        let inside = isInsideOrb(convert(event.locationInWindow, from: nil))
        guard inside != isHovered else { return }
        isHovered = inside
        hoverChanged?(inside)
    }
}
