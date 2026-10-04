#if DIRECT_DISTRIBUTION
import AppKit
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
    let awareness = UpdateAwarenessStore()
    @ObservationIgnored private lazy var driver = UpdateUserDriver(awareness: awareness)
    @ObservationIgnored private lazy var idleInstall = UpdateIdleInstallController(awareness: awareness)
    @ObservationIgnored private lazy var callout = UpdateAwarenessController(awareness: awareness)
    // SPUUpdater holds its delegate weakly.
    @ObservationIgnored private let silentInstall = UpdateSilentInstallDelegate()
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var observations = Set<AnyCancellable>()

    /// Ongoing progress remains reachable even while Sparkle temporarily disallows a new check.
    var canCheckForUpdates: Bool { engineCanCheck || driver.presentation.isActive }
    var updateAvailable: Bool { driver.presentation.updateAvailable }
    var updateInProgress: Bool { driver.presentation.isActive && !updateAvailable }
    /// An automatic install the user has not looked at yet. The menu offers its changelog
    /// instead of a new check until it is opened or a newer offer arrives.
    var showsInstalledNotice: Bool { awareness.installedFromVersion != nil && !driver.presentation.isActive }

    /// Starts once after the dock. No standard Sparkle controller or window is instantiated.
    func start() {
        guard updater == nil else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: silentInstall)
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
        silentInstall.stage = { [weak self] item, install in
            self?.driver.showStagedUpdate(item, install: install)
        }
        driver.requestCheck = { [weak self] in
            guard let self, engineCanCheck else { return }
            self.updater?.checkForUpdates()
        }
        do {
            try updater.start()
        } catch {
            startupFailed = true
            // Startup failures remain in Settings; do not present an unsolicited error on launch.
        }
        idleInstall.isReadyToInstall = { [weak self] in self?.driver.presentation.phase == .ready }
        idleInstall.isWindowVisible = { [weak self] in self?.driver.isWindowVisible ?? false }
        idleInstall.install = { [weak self] in self?.driver.attemptIdleInstall() }
        idleInstall.start()
        callout.openUpdate = { [weak self] in self?.checkForUpdates() }
        callout.openWhatsNew = { [weak self] in self?.showWhatsNew() }
        callout.start()
    }

    /// Idle and callout gates that need dock state. Call after the coordinator exists.
    func bindDesktop(isBusy: @escaping () -> Bool, isIdleBusy: @escaping () -> UpdateIdleGate,
                     targetScreen: @escaping () -> NSScreen?) {
        idleInstall.gateSnapshot = isIdleBusy
        callout.isBlocked = isBusy
        callout.targetScreen = targetScreen
    }

    /// Reopens the current custom session or asks Sparkle to start a fresh user-initiated check.
    func checkForUpdates() {
        if driver.presentation.isActive { driver.showUpdateInFocus() }
        else if engineCanCheck { updater?.checkForUpdates() }
    }

    /// Opens the changelog since the version before the last automatic install and
    /// acknowledges the notice. Falls back to a regular check when there is none.
    func showWhatsNew() {
        guard let previous = awareness.installedFromVersion else { checkForUpdates(); return }
        awareness.acknowledgeInstalled()
        driver.showWhatsNew(since: previous)
    }

    /// Sparkle owns preference persistence and rescheduling.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    /// DOKK-owned idle relaunch. Sparkle is not involved until an install is requested.
    func setInstallWhenIdle(_ enabled: Bool) {
        awareness.setInstallWhenIdle(enabled)
    }

    /// Sparkle persists this preference and uses its silent driver for scheduled checks.
    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
    }

    #if DEBUG
    /// Version the simulated installed notice claims DOKK ran before, old enough that the
    /// changelog spans several real releases.
    private static let debugPreviousVersion = "0.11.2"

    /// Mimics a silent download without Sparkle. Installing ends in the installed notice
    /// instead of a relaunch.
    /// - Parameters:
    ///   - calloutDue: Backdates the download so the ready callout shows at once.
    ///   - idleAfter: Unused-dock seconds before the simulated idle install; nil keeps 10 minutes.
    func debugSimulateDownload(calloutDue: Bool = false, idleAfter: TimeInterval? = nil) {
        debugReset()
        idleInstall.debugIdleThreshold = idleAfter
        driver.debugStage(version: "99.0.0") { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                self?.debugSimulateInstalled()
            }
        }
        // A fresh identity each time, so an earlier dismissal does not hide the marks.
        awareness.noteStagedOffer(identity: "debug-\(UUID().uuidString)", version: "99.0.0",
            now: calloutDue ? Date().addingTimeInterval(-UpdateAwarenessStore.calloutPatience) : Date())
    }

    /// Mimics a scheduled offer that needs the user. Its callout button starts a real check.
    func debugSimulateAvailable() {
        debugReset()
        awareness.noteWaitingOffer(identity: "debug-\(UUID().uuidString)", version: "99.0.0", userInitiated: false)
    }

    /// Mimics the launch after an automatic install.
    func debugSimulateInstalled() {
        debugReset()
        awareness.debugSimulateInstalled(from: Self.debugPreviousVersion)
    }

    func debugReset() {
        idleInstall.debugIdleThreshold = nil
        driver.debugReset()
        awareness.acknowledgeInstalled()
    }
    #endif

    /// Process termination releases presentation, pending responses, and UI observers.
    func stop() {
        callout.stop()
        idleInstall.stop()
        driver.stop()
        driver.requestCheck = {}
        silentInstall.stage = { _, _ in }
        observations.removeAll()
    }
}
#endif
