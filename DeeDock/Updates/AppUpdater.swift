#if DIRECT_DISTRIBUTION
import Combine
import Observation
import Sparkle

/// App-lifetime composition of Sparkle's update engine and DeeDock's complete custom user driver.
@MainActor
@Observable
final class AppUpdater {
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyInstallsUpdates = false
    private(set) var allowsAutomaticUpdates = false
    private(set) var startupFailed = false
    private var engineCanCheck = false
    private let driver = UpdateUserDriver()
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var observations = Set<AnyCancellable>()

    /// Ongoing progress remains reachable even while Sparkle temporarily disallows a new check.
    var canCheckForUpdates: Bool { engineCanCheck || driver.presentation.isActive }
    var updateAvailable: Bool { driver.presentation.updateAvailable }
    var updateInProgress: Bool { driver.presentation.isActive && !updateAvailable }

    /// Starts once after the dock. No standard Sparkle controller or window is instantiated.
    func start() {
        guard updater == nil else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        self.updater = updater
        // The custom consent flow does not offer system-profile sharing.
        updater.sendsSystemProfile = false
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.engineCanCheck = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] in self?.automaticallyInstallsUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.allowsAutomaticUpdates)
            .sink { [weak self] in self?.allowsAutomaticUpdates = $0 }
            .store(in: &observations)
        do {
            try updater.start()
        } catch {
            startupFailed = true
            // Startup failures remain in Settings; do not present an unsolicited error on launch.
        }
    }

    /// Reopens the current custom session or asks Sparkle to start a fresh user-initiated check.
    func checkForUpdates() {
        if driver.presentation.isActive { driver.showUpdateInFocus() }
        else if engineCanCheck { updater?.checkForUpdates() }
    }

    /// Sparkle owns preference persistence and rescheduling.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    /// Sparkle persists this preference and uses its silent driver for scheduled checks.
    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
    }

    /// Process termination releases presentation, pending responses, and UI observers.
    func stop() {
        driver.stop()
        observations.removeAll()
    }
}
#endif
