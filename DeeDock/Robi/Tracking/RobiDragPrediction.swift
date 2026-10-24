import CoreGraphics

/// Where a window is while its title bar is being dragged, predicted from the pointer.
///
/// The window server moves the window from the same mouse events Robi's global monitor sees, so
/// moving the tab by the pointer's delta keeps it on the window (0 pt median offset at 360 pt/s,
/// against 6 pt for SkyLight notifications and 24 pt for AX ones). Coordinates are global
/// top-left points throughout.
nonisolated struct RobiDragPrediction: Equatable {
    /// The height of the band under a window's top edge where a drag is assumed to move it.
    /// Covers title bars and unified toolbars; a drag there that does not move the window is
    /// caught by `isStalled(actual:)` and abandoned.
    static let titleBand: CGFloat = 52
    /// Drag events to wait before checking that the window really follows the pointer.
    static let verificationEvents = 4

    let pointerAtStart: CGPoint
    let frameAtStart: CGRect
    private(set) var events = 0

    /// Nil when the pointer is not in the window's title band.
    init?(pointer: CGPoint, frame: CGRect) {
        guard pointer.x >= frame.minX, pointer.x <= frame.maxX,
              pointer.y >= frame.minY, pointer.y <= frame.minY + min(Self.titleBand, frame.height / 3) else { return nil }
        pointerAtStart = pointer
        frameAtStart = frame
    }

    /// The predicted frame for the current pointer. `topLimit` is the lowest y the window's top
    /// may reach on its screen (the bottom of the menu bar); the window server stops the title
    /// bar there, so the prediction does too.
    mutating func frame(pointer: CGPoint, topLimit: CGFloat) -> CGRect {
        events += 1
        var frame = frameAtStart.offsetBy(dx: pointer.x - pointerAtStart.x, dy: pointer.y - pointerAtStart.y)
        frame.origin.y = max(frame.origin.y, topLimit)
        return frame
    }

    /// True once enough drag events have passed and the window has not moved: the drag started on
    /// a control, a tab, or a text field rather than on the title bar.
    func isStalled(actual: CGRect?) -> Bool {
        guard events >= Self.verificationEvents, let actual else { return false }
        return abs(actual.minX - frameAtStart.minX) < 0.5 && abs(actual.minY - frameAtStart.minY) < 0.5
    }
}
