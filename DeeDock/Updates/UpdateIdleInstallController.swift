#if DIRECT_DISTRIBUTION
import AppKit

/// Watches a ready-to-install offer and asks Sparkle to install once DDock is idle.
///
/// Sparkle still owns download, verify, and install. This type only applies the idle
/// gate and fires one install attempt. If idle never arrives, the existing
/// install-on-quit path remains.
@MainActor
final class UpdateIdleInstallController {
    let awareness: UpdateAwarenessStore
    var isReadyToInstall: () -> Bool = { false }
    var isWindowVisible: () -> Bool = { false }
    var gateSnapshot: () -> UpdateIdleGate = { UpdateIdleGate() }
    var install: () -> Void = {}
    private var timer: Timer?
    #if DEBUG
    /// Shortens the unused-dock period for the update simulation. Busy gates still apply.
    var debugIdleThreshold: TimeInterval?
    #endif

    init(awareness: UpdateAwarenessStore) {
        self.awareness = awareness
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isReadyToInstall = { false }
        isWindowVisible = { false }
        gateSnapshot = { UpdateIdleGate() }
        install = {}
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
#endif
