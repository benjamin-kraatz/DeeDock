import Observation

/// What every dock's DOKK tile shows about the Hub: whether it is open, a pulse when a click
/// brings a detached Hub forward, and file-transfer progress.
///
/// One instance is shared by all docks; the ``HubCoordinator`` writes it.
@MainActor @Observable
final class HubTileState {
    /// The Hub is on screen, anchored or detached. The tile's halo brightens and grows.
    private(set) var isOpen = false
    /// Incremented when a tile click brings a detached Hub to the front; the tile pulses.
    private(set) var pulse = 0
    /// Overall progress of copies and moves in the Files tab, or nil when none run. Reading it
    /// inside a view body tracks the Files model, so the ring follows without polling.
    @ObservationIgnored var transferProgress: () -> Double? = { nil }

    init() {}

    /// Updates the open state. Only the Hub's owner calls this.
    func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
    }

    /// Plays one tile pulse.
    func playPulse() { pulse += 1 }
}
