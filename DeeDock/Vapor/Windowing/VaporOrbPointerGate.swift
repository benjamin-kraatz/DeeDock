import AppKit

/// Lets the orb's window take the pointer only while it is over the sphere.
///
/// The sphere is Liquid Glass, which the window server composites outside the window's backing.
/// A non-opaque window hit-tests on its own pixels, so it reads the glass as transparent and
/// passes clicks, drags and drops on the orb to the window behind it. Only an explicit
/// `ignoresMouseEvents` turns that alpha hit-testing off, and an explicit `false` would also
/// catch clicks on the transparent margin around the orb, where the suggestion bubbles sit. So
/// this follows the pointer with a global and a local event monitor (mouse monitors need no
/// Accessibility trust) and sets `false` over the sphere and `true` everywhere else, as the
/// dock's panels do. File drags from Finder arrive as dragged events too, so the orb becomes a
/// drop target as a drag reaches it.
///
/// Monitors exist only between `start()` and `stop()`.
@MainActor
final class VaporOrbPointerGate {
    private let view: VaporOrbInteractionView
    private var monitors: [Any] = []

    init(view: VaporOrbInteractionView) {
        self.view = view
    }

    /// Installs the monitors, if needed, and applies the gate for where the pointer is now.
    /// Call after the window is shown: the panel is deferred, so a value set before it is on
    /// screen may not reach the window server.
    func start() {
        if monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                               .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.view.updatePointerGate() }
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.view.updatePointerGate()
                return event
            }) {
                monitors.append(local)
            }
        }
        view.updatePointerGate(force: true)
    }

    /// Removes the monitors.
    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
