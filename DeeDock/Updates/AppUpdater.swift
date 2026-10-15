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
    @ObservationIgnored private let analytics = UpdateAnalytics()
    @ObservationIgnored private lazy var driver = UpdateUserDriver(awareness: awareness, analytics: analytics)
    @ObservationIgnored private lazy var idleInstall = UpdateIdleInstallController(awareness: awareness)
    /// The driver's island also shows awareness callouts between sessions.
    @ObservationIgnored private var callout: UpdateIslandController { driver.island }
    // SPUUpdater holds its delegate weakly.
    @ObservationIgnored private let engineDelegate = UpdateEngineDelegate()
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
        analytics.snapshot = { [weak self] in self?.analyticsSnapshot ?? UpdateAnalytics.Snapshot() }
        analytics.reportLaunch()
        engineDelegate.analytics = analytics
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: engineDelegate)
        self.updater = updater
        // The custom consent flow does not offer system-profile sharing.
        updater.sendsSystemProfile = false
        // Before `start`, so the first schedule uses the floor. User defaults override the
        // Info.plist interval, and enabling checks from a zero interval restores Sparkle's
        // one-day default. The publisher covers that later change.
        applyAutomaticCheckInterval()
        updater.publisher(for: \.updateCheckInterval)
            .sink { [weak self] _ in self?.applyAutomaticCheckInterval() }
            .store(in: &observations)
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
        engineDelegate.stage = { [weak self] item, install in
            self?.driver.showStagedUpdate(item, install: install)
        }
        engineDelegate.backgroundDiscovery = { [weak self] item in
            self?.awareness.noteBackgroundDiscovery(identity: item.versionString)
        }
        engineDelegate.cancelBackgroundDiscovery = { [weak self] in
            self?.awareness.discardPendingBackgroundDiscovery()
        }
        driver.requestCheck = { [weak self] in self?.checkForUpdates(source: .checkAgain) }
        do {
            try updater.start()
        } catch {
            startupFailed = true
            analytics.startupFailed(error)
            // Startup failures remain in Settings; do not present an unsolicited error on launch.
        }
        idleInstall.isReadyToInstall = { [weak self] in self?.driver.presentation.phase == .ready }
        idleInstall.isWindowVisible = { [weak self] in self?.driver.isWindowVisible ?? false }
        idleInstall.install = { [weak self] in self?.driver.attemptIdleInstall() }
        idleInstall.start()
        callout.openUpdate = { [weak self] in self?.checkForUpdates(source: .callout) }
        callout.openWhatsNew = { [weak self] in self?.showWhatsNew(source: .callout) }
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
    /// - Parameter source: Where the person asked, reported to analytics.
    func checkForUpdates(source: AnalyticsUpdateSource) {
        if driver.presentation.isActive {
            analytics.opened(source, target: .currentSession)
            driver.showUpdateInFocus()
        } else if engineCanCheck, let updater {
            analytics.opened(source, target: .newCheck)
            updater.checkForUpdates()
        } else {
            analytics.opened(source, target: .unavailable)
        }
    }

    /// Opens the changelog since the version before the last automatic install and
    /// acknowledges the notice. Falls back to a regular check when there is none.
    /// - Parameter source: Where the person asked, reported to analytics.
    func showWhatsNew(source: AnalyticsUpdateSource) {
        guard let previous = awareness.installedFromVersion else { checkForUpdates(source: source); return }
        analytics.opened(source, target: .whatsNew)
        awareness.acknowledgeInstalled()
        driver.showWhatsNew(since: previous, source: source)
    }

    /// Sparkle 2.9.6 waits at least this long between automatic checks.
    ///
    /// `SPUUpdaterSettings.minimumUpdateCheckInterval` is one hour in a release build. The
    /// scheduler raises any shorter `updateCheckInterval`, including 30 minutes, to this value
    /// when it arms the timer. The setter itself does not clamp.
    nonisolated static let automaticCheckInterval: TimeInterval = 60 * 60

    /// The interval to write when `current` is not already the floor.
    ///
    /// Zero is Sparkle's legacy way to turn checks off, so it is left alone. A stored day, or
    /// any other positive interval, is replaced with ``automaticCheckInterval``.
    nonisolated static func enforcedUpdateCheckInterval(current: TimeInterval) -> TimeInterval? {
        guard current > 0, abs(current - automaticCheckInterval) > 0.5 else { return nil }
        return automaticCheckInterval
    }

    /// Replaces a persisted interval Sparkle would otherwise keep using.
    ///
    /// `SUScheduledCheckInterval` in Info.plist is only the default. User defaults win, so a
    /// one-day value stored before the plist key existed keeps a new release waiting out the
    /// rest of that day until this writes the floor.
    private func applyAutomaticCheckInterval() {
        guard let updater, let interval = Self.enforcedUpdateCheckInterval(current: updater.updateCheckInterval) else { return }
        updater.updateCheckInterval = interval
    }

    /// Sparkle owns preference persistence and rescheduling.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        let old = settings
        updater?.automaticallyChecksForUpdates = enabled
        reportSettings(from: old) { $0.checkAutomatically = enabled }
    }

    /// DOKK-owned idle relaunch. Sparkle is not involved until an install is requested.
    func setInstallWhenIdle(_ enabled: Bool) {
        let old = settings
        awareness.setInstallWhenIdle(enabled)
        reportSettings(from: old) { $0.installWhenIdle = enabled }
    }

    /// Sparkle persists this preference and uses its silent driver for scheduled checks.
    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        let old = settings
        updater?.automaticallyDownloadsUpdates = enabled
        reportSettings(from: old) { $0.installAutomatically = enabled }
    }

    /// The update preferences as `setting_changed` reports them, with `area = updates`.
    private struct Settings {
        var checkAutomatically: Bool
        var installAutomatically: Bool
        var installWhenIdle: Bool
    }

    private var settings: Settings {
        Settings(checkAutomatically: automaticallyChecksForUpdates, installAutomatically: automaticallyInstallsUpdates,
                 installWhenIdle: awareness.installWhenIdle)
    }

    /// The published Sparkle values follow through KVO a moment later, so the new value is
    /// applied to the old snapshot rather than read back.
    private func reportSettings(from old: Settings, change: (inout Settings) -> Void) {
        var new = old
        change(&new)
        Analytics.shared.settingsChanged(from: old, to: new, area: .updates)
    }

    private var analyticsSnapshot: UpdateAnalytics.Snapshot {
        let presentation = driver.presentation
        return UpdateAnalytics.Snapshot(
            checksAutomatically: automaticallyChecksForUpdates, installsAutomatically: automaticallyInstallsUpdates,
            installsWhenIdle: awareness.installWhenIdle, automaticInstallAllowed: allowsAutomaticUpdates,
            phase: presentation.phase, staged: presentation.staged, stagedSince: awareness.stagedSince,
            expectedBytes: presentation.expectedBytes, receivedBytes: presentation.receivedBytes)
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
        // Before the driver resets its phase, which tells whether Sparkle installs on quit.
        analytics.reportTermination()
        callout.stop()
        idleInstall.stop()
        driver.stop()
        driver.requestCheck = {}
        engineDelegate.stage = { _, _ in }
        engineDelegate.backgroundDiscovery = { _ in }
        engineDelegate.cancelBackgroundDiscovery = {}
        engineDelegate.analytics = nil
        observations.removeAll()
    }
}
