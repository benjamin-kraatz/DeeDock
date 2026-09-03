import CoreGraphics

/// Whether the macOS Dock is currently holding desktop space away from the user.
///
/// This measures reserved space, not the `com.apple.dock` `autohide` preference: an App Sandbox
/// cannot read another application's defaults domain, and DeeDock must never write that
/// preference (see `AGENTS.md`). Turning on *Automatically hide and show the Dock* releases the
/// reserved band and is therefore observable here; simply moving the Dock to another edge is not,
/// which is the intended answer, because the Dock still occupies the desktop either way.
enum SystemDockReservation {
    /// Fractional insets appear on scaled displays, so a sub-point difference is not a reservation.
    static let tolerance: CGFloat = 1

    /// The edge whose desktop space this screen currently gives up, or nil when it gives up none.
    ///
    /// The top inset is deliberately excluded: the menu bar and the notch reserve it on every
    /// screen, and macOS never places the Dock there. Both rectangles are AppKit screen
    /// coordinates, so `visibleFrame` is inset within `frame` and origins may be negative.
    static func reservedEdge(frame: CGRect, visibleFrame: CGRect) -> DockEdge? {
        guard !frame.isEmpty, !visibleFrame.isEmpty else { return nil }
        let bottom = visibleFrame.minY - frame.minY
        let left = visibleFrame.minX - frame.minX
        let right = frame.maxX - visibleFrame.maxX
        // A Dock occupies exactly one edge, so the largest qualifying inset identifies it.
        let candidates: [(DockEdge, CGFloat)] = [(.bottom, bottom), (.left, left), (.right, right)]
        guard let widest = candidates.filter({ $0.1 > tolerance }).max(by: { $0.1 < $1.1 }) else { return nil }
        return widest.0
    }

    /// The first screen still reserving space, so a person with several displays is told that
    /// the Dock is in the way somewhere rather than only about the screen they happen to face.
    static func reservedEdge(in screens: [(frame: CGRect, visibleFrame: CGRect)]) -> DockEdge? {
        screens.lazy.compactMap { reservedEdge(frame: $0.frame, visibleFrame: $0.visibleFrame) }.first
    }
}
