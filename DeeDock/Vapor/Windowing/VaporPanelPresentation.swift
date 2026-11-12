import CoreGraphics
import Observation

/// What the panel window shows and where, written by ``VaporWindows`` and read by
/// ``VaporPanelStage``.
///
/// The panel's window is larger than the panel: it also covers the orb, so the panel can grow
/// out of the orb and rows can fly into it without being clipped by the window. Positions are
/// in the window's SwiftUI coordinates (origin top-left, y down).
@MainActor @Observable
final class VaporPanelPresentation {
    /// True while the panel is grown out of the orb; false shrinks it back in.
    var isShown = false
    /// The panel's top-left corner inside the window.
    var panelOrigin: CGPoint = .zero
    /// The orb's centre inside the window: the grow anchor and where rows fly on delete.
    var orbPoint: CGPoint = .zero
    /// The delete whose rows are flying into the orb, or nil.
    var pull: VaporDeletion?

    /// The panel's laid-out size, once the stage has measured it.
    @ObservationIgnored private(set) var panelSize: CGSize?
    /// Called when the measured size changes, so the window is resized and re-placed.
    @ObservationIgnored var sizeChanged: (() -> Void)?

    /// Records the panel's size from the stage. Reports a change on the next main-actor turn,
    /// outside SwiftUI's layout pass.
    func report(size: CGSize) {
        guard size.width > 0, size.height > 0, size != panelSize else { return }
        panelSize = size
        Task { @MainActor [weak self] in self?.sizeChanged?() }
    }
}
