import SwiftUI
import Observation

/// One panel's idle deadline. Opacity never changes native hit testing or auto-hide state.
/// The owner refreshes pointer input before a deadline and stops this controller on teardown.
@MainActor @Observable
final class DockIdleFadeController {
    private struct Configuration: Equatable {
        let enabled: Bool
        let opacity: Double
        let delay: Double
        let fadeOut: Double
        let restore: Double
        let target: DockSettings.FadeTarget
        let showBackground: Bool
        let backgroundOpacity: Double
        let reduceMotion: Bool
        let reduceTransparency: Bool
    }

    private(set) var fraction: Double = 0
    /// Scoped to opacity so hover springs cannot change the configured fade timing.
    private(set) var animation: Animation?
    private(set) var settings = DockSettings.defaults
    private(set) var reduceTransparency = false
    @ObservationIgnored var refreshInput: (() -> Void)?
    @ObservationIgnored private var configuration: Configuration?
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var pending: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var eligible = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var reduceMotion = false

    init(scheduler: (any DockVisibilityScheduling)? = nil) {
        self.scheduler = scheduler ?? DockVisibilityScheduler()
    }

    /// Accessibility overrides are effective-only; saved preferences remain unchanged.
    func configure(_ settings: DockSettings, reduceMotion: Bool, reduceTransparency: Bool) {
        let next = Configuration(enabled: settings.fadeWhenIdle, opacity: settings.idleOpacity,
            delay: settings.idleDelay, fadeOut: settings.fadeOutDuration, restore: settings.restoreDuration,
            target: settings.fadeTarget, showBackground: settings.showBackground,
            backgroundOpacity: settings.backgroundOpacity, reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency)
        // Drawing also reads appearance values that do not restart the idle timer.
        self.settings = settings
        guard configuration != next else { return }
        configuration = next
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        reset()
    }

    /// Only a fully revealed dock can begin an idle period. Repeated input preserves its deadline.
    func update(interacting: Bool, fullyVisible: Bool) {
        guard !stopped else { return }
        let next = fullyVisible && !interacting && settings.fadeWhenIdle && !reduceTransparency
        guard next != eligible else { return }
        eligible = next
        cancelDeadline()
        if !next {
            // Hidden/revealing docks restore immediately so every reveal begins at normal opacity.
            setFraction(0, duration: fullyVisible && !reduceMotion ? settings.restoreDuration : 0)
            return
        }
        let token = generation
        pending = scheduler.schedule(after: settings.idleDelay) { [weak self] in
            guard let self, !stopped, generation == token else { return }
            refreshInput?()
            guard !stopped, eligible, generation == token else { return }
            pending = nil
            setFraction(1, duration: reduceMotion ? min(0.1, settings.fadeOutDuration) : settings.fadeOutDuration)
        }
    }

    /// Clears stale timing after a display, Space, or sleep/wake refresh.
    func reset() {
        eligible = false
        cancelDeadline()
        setFraction(0, duration: 0)
    }

    private func setFraction(_ value: Double, duration: Double) {
        animation = duration == 0 ? nil : .easeInOut(duration: duration)
        guard fraction != value else { return }
        withAnimation(animation) { fraction = value }
    }

    private func cancelDeadline() {
        generation = UUID()
        pending?.cancel()
        pending = nil
    }

    func stop() {
        stopped = true
        reset()
        refreshInput = nil
    }
}
