import Foundation
import Observation

/// Badges, pip, and callout state for a waiting or freshly installed DOKK update.
///
/// Waiting-offer indicators stay up until the Update window opens, the callout is dismissed,
/// or the offer is installed or skipped. After that, this process stays quiet for the same
/// offer identity. A later identity or a new launch can show them again.
///
/// A silently downloaded ("staged") offer shows the badge and pip at once but holds its
/// callout back while idle install can still take care of it. An automatic install leaves a
/// persisted record, so the next launch can say that DOKK was updated until the user
/// acknowledges it or a newer offer arrives.
@MainActor
@Observable
final class UpdateAwarenessStore {
    /// Preference for hands-off install after a downloaded update. Default is on. The `v1`
    /// key defaulted to off and could not tell an opt-out from an untouched default, so it
    /// is not migrated.
    static let idleInstallKey = "updates.install-when-idle.v2"
    /// How long a staged offer may wait for idle install before the callout asks for attention.
    static let calloutPatience: TimeInterval = 2 * 60 * 60

    private(set) var showsIndicators = false
    private(set) var offerIdentity: String?
    private(set) var offerVersion: String?
    /// When the current offer finished its silent download. Nil for offers that need the user.
    private(set) var stagedSince: Date?
    private(set) var windowIsOpen = false
    private(set) var idleInstallAttempted = false
    private(set) var installWhenIdle: Bool
    /// Version DOKK ran before an automatic install that has not been acknowledged yet.
    private(set) var installedFromVersion: String?
    /// The post-install callout and dock pip show once per automatic install.
    private(set) var showsInstalledCallout = false
    private var dismissedIdentities: Set<String> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let currentBuild: String?

    /// - Parameters:
    ///   - currentVersion: Marketing version of the running app, recorded before an automatic
    ///     install. Nil reads both version and build from the main bundle.
    ///   - currentBuild: Build of the running app, used only with an explicit `currentVersion`.
    ///     A persisted install record with another build means that install completed; the
    ///     same build means it did not, and the record is discarded.
    init(defaults: UserDefaults = .standard, currentVersion: String? = nil, currentBuild: String? = nil) {
        self.defaults = defaults
        self.currentVersion = currentVersion ?? AppVersionInfo.current.version
        self.currentBuild = currentVersion == nil ? AppVersionInfo.current.build : currentBuild
        let currentBuild = self.currentBuild
        installWhenIdle = defaults.object(forKey: Self.idleInstallKey) as? Bool ?? true
        if let record = UpdateInstallRecord.load(from: defaults) {
            if record.completed(currentBuild: currentBuild) {
                installedFromVersion = record.fromVersion
                showsInstalledCallout = !record.announced
            } else {
                UpdateInstallRecord.clear(in: defaults)
            }
        }
    }

    #if DEBUG
    /// Isolated defaults so canvas interaction cannot write the live preference.
    static func previewStore(idleInstall: Bool = false) -> UpdateAwarenessStore {
        let defaults = UserDefaults(suiteName: "preview.updates.awareness.\(UUID().uuidString)") ?? .standard
        let store = UpdateAwarenessStore(defaults: defaults)
        store.setInstallWhenIdle(idleInstall)
        return store
    }
    #endif

    #if DEBUG
    /// Shows the post-install notice without an install and without writing the record.
    func debugSimulateInstalled(from previousVersion: String) {
        installedFromVersion = previousVersion
        showsInstalledCallout = true
    }
    #endif

    func setInstallWhenIdle(_ enabled: Bool) {
        guard enabled != installWhenIdle else { return }
        installWhenIdle = enabled
        defaults.set(enabled, forKey: Self.idleInstallKey)
    }

    /// Records a waiting offer that needs the user. A user-initiated check opens the Update
    /// window, so it acknowledges without showing indicators.
    func noteWaitingOffer(identity: String, version: String, userInitiated: Bool) {
        let changed = offerIdentity != identity
        offerIdentity = identity
        offerVersion = version
        if changed {
            idleInstallAttempted = false
            stagedSince = nil
        }
        acknowledgeInstalled()
        if userInitiated {
            acknowledge()
            return
        }
        showsIndicators = !dismissedIdentities.contains(identity)
    }

    /// Records an offer Sparkle downloaded silently. The badge and pip show at once. The
    /// callout follows `showsCallout(now:)`.
    func noteStagedOffer(identity: String, version: String, now: Date = Date()) {
        if offerIdentity != identity || stagedSince == nil {
            idleInstallAttempted = false
            stagedSince = now
        }
        offerIdentity = identity
        offerVersion = version
        acknowledgeInstalled()
        showsIndicators = !dismissedIdentities.contains(identity)
    }

    /// Whether the waiting-offer callout should be up. A staged offer stays quiet while idle
    /// install is on and has had less than `calloutPatience` to run.
    func showsCallout(now: Date = Date()) -> Bool {
        guard showsIndicators, offerVersion != nil, !windowIsOpen else { return false }
        guard let stagedSince, installWhenIdle else { return true }
        return now.timeIntervalSince(stagedSince) >= Self.calloutPatience
    }

    /// The dock's update tile. It stays while an offer waits, and after an automatic install
    /// until the changelog is opened, so the update can always be reached from the dock.
    var dockItem: UpdateDockItem? {
        if let offerVersion {
            return UpdateDockItem(state: stagedSince == nil ? .available : .ready, version: offerVersion)
        }
        if installedFromVersion != nil { return UpdateDockItem(state: .installed, version: currentVersion) }
        return nil
    }

    /// Pip on DOKK's own tile for a waiting offer or a not-yet-announced automatic install.
    var showsDockPip: Bool { showsIndicators || showsInstalledCallout }
    /// Menu-bar badge. Unlike the pip it stays until the installed notice is acknowledged.
    var showsMenuBadge: Bool { showsIndicators || installedFromVersion != nil }

    func noteWindowOpened() {
        windowIsOpen = true
        acknowledge()
    }

    func noteWindowClosed() {
        windowIsOpen = false
    }

    /// Hides indicators for this offer until a new identity or the next launch.
    func dismiss() {
        acknowledge()
    }

    /// Clears the waiting offer after install, skip, or Sparkle dismissal of the session.
    func noteSessionEnded() {
        showsIndicators = false
        offerIdentity = nil
        offerVersion = nil
        stagedSince = nil
        windowIsOpen = false
        idleInstallAttempted = false
    }

    func markIdleInstallAttempted() {
        idleInstallAttempted = true
    }

    /// Idle install needs a downloaded offer, the preference, a free Update window, and
    /// no prior attempt in this session.
    var canAttemptIdleInstall: Bool {
        installWhenIdle && !idleInstallAttempted && !windowIsOpen && offerIdentity != nil
    }

    /// Persists the running version right before an automatic install replaces the app.
    /// The next launch compares builds to learn whether that install completed.
    func recordAutomaticInstall() {
        UpdateInstallRecord(fromVersion: currentVersion, fromBuild: currentBuild, announced: false)
            .save(to: defaults)
    }

    /// The post-install callout was opened or dismissed. The menu notice stays.
    func noteInstalledCalloutSeen() {
        guard showsInstalledCallout else { return }
        showsInstalledCallout = false
        guard var record = UpdateInstallRecord.load(from: defaults) else { return }
        record.announced = true
        record.save(to: defaults)
    }

    /// The user opened the installed notice, or a newer offer replaced it.
    func acknowledgeInstalled() {
        guard installedFromVersion != nil else { return }
        installedFromVersion = nil
        showsInstalledCallout = false
        UpdateInstallRecord.clear(in: defaults)
    }

    private func acknowledge() {
        if let offerIdentity { dismissedIdentities.insert(offerIdentity) }
        showsIndicators = false
    }
}

/// Snapshot of whether DDock is free to install and relaunch.
///
/// Dock use is measured by the caller. The busy flags are the strict gates from DEE-76
/// plus file-picker, dock popover, Window Peek, and menu-tracking states that are equally
/// "in the middle of something."
struct UpdateIdleGate: Equatable, Sendable {
    var isDragging = false
    var isFocusSessionPanelOpen = false
    var isUpdateWindowOpen = false
    var isFilePickerActive = false
    var isPopoverOpen = false
    var isMenuTracking = false
    var isWindowPeekOpen = false
    /// Seconds since the pointer or a held interaction last touched any dock.
    var secondsSinceDockUse: TimeInterval = 0

    /// How long every dock must go unused before DOKK counts as idle.
    static let idleThreshold: TimeInterval = 10 * 60

    var isBusy: Bool {
        isDragging || isFocusSessionPanelOpen || isUpdateWindowOpen
            || isFilePickerActive || isPopoverOpen || isMenuTracking || isWindowPeekOpen
    }

    var isIdle: Bool {
        !isBusy && secondsSinceDockUse >= Self.idleThreshold
    }
}
