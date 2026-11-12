import AppKit

/// The orb window's content view: click, drag to move, right-click, hover and file drops.
///
/// Only the sphere itself is interactive. ``VaporOrbPointerGate`` makes the window ignore the
/// pointer everywhere else, so the transparent canvas around the orb lets clicks fall through to
/// the window below, and `hitTest` returns nil outside the sphere as a second line. Mouse events
/// reach this view instead of the SwiftUI subview because hit-testing returns `self`; the
/// SwiftUI view still provides the accessibility element. Hover comes from the gate too.
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
    private var isHovered = false
    /// The last value the gate gave the window's `ignoresMouseEvents`, so the window server is
    /// only told about changes. Nil until the first explicit value.
    private var gateIgnores: Bool?

    private var orbCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return VaporGeometry.isOnOrb(local, orbCenter: orbCenter) ? self : nil
    }

    /// Takes the pointer while it is over the sphere or a press that started there is held, and
    /// passes it through otherwise; also updates hover. Called by ``VaporOrbPointerGate``.
    /// - Parameter force: Sets `ignoresMouseEvents` even when the gate's last value matches,
    ///   for a window that was just shown.
    func updatePointerGate(force: Bool = false) {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let onOrb = window.isVisible && VaporGeometry.isOnOrb(point, orbCenter: orbCenter)
        let ignores = !(onOrb || pressLocation != nil)
        if force || gateIgnores != ignores {
            gateIgnores = ignores
            window.ignoresMouseEvents = ignores
        }
        setHovered(onOrb)
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
            // A move can end with the pointer off the orb; let the next click through.
            updatePointerGate()
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
        // The menu tracks the pointer itself, so it may have left the orb meanwhile.
        updatePointerGate()
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        hoverChanged?(hovered)
    }
}
