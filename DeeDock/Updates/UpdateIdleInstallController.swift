import AppKit
import Observation

/// Watches a ready-to-install offer and asks Sparkle to install once DDock is idle.
///
/// Sparkle still owns download, verify, and install. This type only applies the idle
/// gate and fires one install attempt. If idle never arrives, the existing
/// install-on-quit path remains.
@MainActor
final class UpdateIdleInstallController {
    let awareness: UpdateAwarenessStore
    /// Whether Sparkle holds a downloaded update. It must read Observation-tracked state (the app
    /// passes `UpdatePresentation.phase`): the 1 Hz check is armed only while this and
    /// `awareness.canAttemptIdleInstall` hold, and is re-armed when the state it reads changes.
    var isReadyToInstall: () -> Bool = { false } {
        didSet { if started { restartTracking() } }
    }
    var isWindowVisible: () -> Bool = { false }
    var gateSnapshot: () -> UpdateIdleGate = { UpdateIdleGate() }
    var install: () -> Void = {}
    private var timer: Timer?
    /// True between `start()` and `stop()`.
    private var started = false
    /// Bumped whenever the observation chain restarts, so a stale registration cannot fork a second chain.
    private var trackingGeneration = 0
    #if DEBUG
    /// Shortens the unused-dock period for the update simulation. Busy gates still apply.
    var debugIdleThreshold: TimeInterval?
    #endif

    init(awareness: UpdateAwarenessStore) {
        self.awareness = awareness
    }

    func start() {
        guard !started else { return }
        started = true
        restartTracking()
    }

    func stop() {
        started = false
        trackingGeneration += 1
        timer?.invalidate()
        timer = nil
        isReadyToInstall = { false }
        isWindowVisible = { false }
        gateSnapshot = { UpdateIdleGate() }
        install = {}
    }

    private func restartTracking() {
        trackingGeneration += 1
        trackReadiness()
    }

    /// Runs the 1 Hz idle check only while an install could be attempted. The busy gates and dock
    /// idle time change without notifications, so they are still polled while armed; readiness
    /// itself is observed. Observation fires once, so each change registers the next one.
    private func trackReadiness() {
        guard started else { return }
        let generation = trackingGeneration
        let armed = withObservationTracking {
            awareness.canAttemptIdleInstall && isReadyToInstall()
        } onChange: { [weak self] in
            guard let self else { return }
            // `onChange` runs before the new value is stored; read it on the next main-actor turn.
            Task { @MainActor in
                guard self.started, self.trackingGeneration == generation else { return }
                self.trackReadiness()
            }
        }
        setTimerArmed(armed)
    }

    private func setTimerArmed(_ armed: Bool) {
        guard armed else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Evaluates the current gate. Tests call this without starting the timer.
    func tick() {
        guard awareness.canAttemptIdleInstall, isReadyToInstall() else { return }
        var gate = gateSnapshot()
        gate.isUpdateWindowOpen = gate.isUpdateWindowOpen || isWindowVisible() || awareness.windowIsOpen
        #if DEBUG
        if let debugIdleThreshold {
            guard !gate.isBusy, gate.secondsSinceDockUse >= debugIdleThreshold else { return }
        } else {
            guard gate.isIdle else { return }
        }
        #else
        guard gate.isIdle else { return }
        #endif
        awareness.markIdleInstallAttempted()
        install()
    }
}
