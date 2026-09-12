#if DIRECT_DISTRIBUTION
import Foundation
import Observation

/// Session-scoped badges, pip, and callout for a waiting DDock update.
///
/// Indicators stay up until the Update window opens, the callout is dismissed, or the
/// offer is installed or skipped. After that, this process stays quiet for the same
/// offer identity. A later identity or a new launch can show them again. Scheduled
/// Sparkle checks of the same offer do not repeat the callout.
@MainActor
@Observable
final class UpdateAwarenessStore {
    /// Preference for hands-off install after a downloaded update. Default is off.
    static let idleInstallKey = "updates.install-when-idle.v1"

    private(set) var showsIndicators = false
    private(set) var offerIdentity: String?
    private(set) var offerVersion: String?
    private(set) var windowIsOpen = false
    private(set) var idleInstallAttempted = false
    private(set) var installWhenIdle: Bool
    private var dismissedIdentities: Set<String> = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        installWhenIdle = defaults.bool(forKey: Self.idleInstallKey)
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

    func setInstallWhenIdle(_ enabled: Bool) {
        guard enabled != installWhenIdle else { return }
        installWhenIdle = enabled
        defaults.set(enabled, forKey: Self.idleInstallKey)
    }

    /// Records a waiting offer. A user-initiated check opens the Update window, so it
    /// acknowledges without showing indicators.
    func noteWaitingOffer(identity: String, version: String, userInitiated: Bool) {
        let changed = offerIdentity != identity
        offerIdentity = identity
        offerVersion = version
        if changed { idleInstallAttempted = false }
        if userInitiated {
            acknowledge()
            return
        }
        showsIndicators = !dismissedIdentities.contains(identity)
    }

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

    private func acknowledge() {
        if let offerIdentity { dismissedIdentities.insert(offerIdentity) }
        showsIndicators = false
    }
}

/// Snapshot of whether DDock is free to install and relaunch.
///
/// Input idle is measured by the caller. The busy flags are the strict gates from DEE-76
/// plus file-picker, dock popover, and menu-tracking states that are equally "in the middle
/// of something."
struct UpdateIdleGate: Equatable, Sendable {
    var isDragging = false
    var isFocusSessionPanelOpen = false
    var isUpdateWindowOpen = false
    var isFilePickerActive = false
    var isPopoverOpen = false
    var isMenuTracking = false
    var secondsSinceInput: TimeInterval = 0

    /// Quiet period after the last HID event before DDock counts as idle.
    static let idleInputThreshold: TimeInterval = 30

    var isBusy: Bool {
        isDragging || isFocusSessionPanelOpen || isUpdateWindowOpen
            || isFilePickerActive || isPopoverOpen || isMenuTracking
    }

    var isIdle: Bool {
        !isBusy && secondsSinceInput >= Self.idleInputThreshold
    }
}
#endif
