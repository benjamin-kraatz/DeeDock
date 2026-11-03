import SwiftUI
import Observation

/// Replays one app-name preset at a time in the Settings gallery, with the dock's own timing.
///
/// The delay, entrance animation, and transition all come from `DockTooltipPreset`, the same
/// values `DockTooltipController` and `DockTooltipsOverlay` apply in the dock. Only the hidden
/// starting state differs: a gallery thumbnail shows its label while idle, so playback first hides
/// it without animation, then reveals it after the preset's delay inside the preset's animation.
///
/// At most one reveal is pending. Starting another preset, `stop`, and the owner's lifecycle
/// callbacks cancel it, so no scheduled work outlives the hovered card.
@MainActor @Observable
final class DockTooltipPresetPlayback {
    /// What one gallery card shows.
    enum Phase: Equatable {
        /// Static thumbnail with its label.
        case idle
        /// Hovered or focused, label hidden until the preset's hover delay passes.
        case waiting
        /// The label has entered; the card looks idle again until the pointer leaves.
        case revealed
    }

    /// The preset currently replaying, or nil while every card is idle.
    private(set) var preset: DockTooltipPreset?
    private(set) var revealed = false
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var pending: DockScheduledAction?
    @ObservationIgnored private var generation = 0

    /// Not a preset timing. The dock starts from no label, but a zero-delay animated entrance in
    /// the gallery starts from a visible one, so it waits one display frame for the hidden state
    /// to render before it can animate in.
    private static let hiddenFrame: TimeInterval = 1.0 / 60

    init(scheduler: (any DockVisibilityScheduling)? = nil) {
        self.scheduler = scheduler ?? DockVisibilityScheduler()
    }

    /// The phase to draw for `preset`'s card.
    func phase(for preset: DockTooltipPreset) -> Phase {
        guard self.preset == preset else { return .idle }
        return revealed ? .revealed : .waiting
    }

    /// Hides `preset`'s label at once and reveals it after its hover delay, cancelling any other
    /// card's playback. An instant, immediate preset has nothing to replay: the dock shows its label
    /// in the same update, which is what the idle thumbnail already shows.
    func play(_ preset: DockTooltipPreset, reduceMotion: Bool) {
        stop()
        let animation = preset.animation(reduceMotion: reduceMotion)
        guard preset != .off, preset.delay > 0 || animation != nil else { return }
        withoutAnimation { self.preset = preset; revealed = false }
        generation &+= 1
        let token = generation
        pending = scheduler.schedule(after: max(preset.delay, Self.hiddenFrame)) { [weak self] in
            guard let self, generation == token else { return }
            pending = nil
            withAnimation(animation) { self.revealed = true }
        }
    }

    /// Cancels the pending reveal and returns every card to its static thumbnail without animation.
    /// - Parameter preset: Stops only if this preset is the one replaying; nil stops any playback.
    func stop(_ preset: DockTooltipPreset? = nil) {
        if let preset, preset != self.preset { return }
        generation &+= 1
        pending?.cancel()
        pending = nil
        guard self.preset != nil else { return }
        withoutAnimation { self.preset = nil; revealed = false }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}
