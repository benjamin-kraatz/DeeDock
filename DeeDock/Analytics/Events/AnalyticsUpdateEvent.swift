import Foundation

/// One step of the update flow, sent as `update_<name>` together with ``AnalyticsUpdateFacts``.
///
/// The Sparkle engine, the custom user driver, the update island, and the next launch each
/// report the steps they see. ``UpdateAnalytics`` turns their callbacks into these cases.
/// `docs/ANALYTICS.md` lists every event with its properties.
enum AnalyticsUpdateEvent {
    /// A menu item, the Settings button, the dock tile, or a callout asked for the update UI.
    case opened(source: AnalyticsUpdateSource, target: AnalyticsUpdateOpenTarget)
    /// Sparkle asked whether it may check automatically. The answer is an ``action(_:via:)``.
    case permissionRequested
    /// Sparkle began an update cycle. `source` is set for checks a person started.
    case checkStarted(AnalyticsUpdateCheck, source: AnalyticsUpdateSource?)
    case found(AnalyticsUpdateCheck?, userInitiated: Bool, duration: Double?)
    case notFound(AnalyticsUpdateCheck?, reason: AnalyticsUpdateNotFoundReason, latestVersion: AnalyticsVersion?,
                  latestBuild: Int?, userInitiated: Bool, duration: Double?)
    /// The custom driver received an offer that needs a person. `presented` is false for a
    /// scheduled offer, which waits behind the badge, tile, and callout.
    case offerShown(stage: UpdateOffer.Stage, userInitiated: Bool, presented: Bool)
    /// `silent` means Sparkle's automatic driver is downloading without any UI.
    case downloadStarted(silent: Bool)
    case downloadFinished(AnalyticsOutcome, silent: Bool, duration: Double?, expectedBytes: Int?,
                          receivedBytes: Int?, error: AnalyticsUpdateError?)
    case extracted(silent: Bool, duration: Double?)
    /// The update is downloaded and prepared and only needs an install and relaunch.
    case ready(silent: Bool, duration: Double?)
    /// A button in the update panel, closing the panel, or idle install.
    case action(UpdateAction, via: AnalyticsUpdateActionVia)
    case installStarted(path: AnalyticsUpdateInstallPath, silent: Bool, waited: Double?)
    /// The installer is waiting for DOKK to quit and something refused termination.
    case installWaitingForQuit
    /// Sent on the first launch of a new build. `path` is `manual` when DOKK did not start
    /// the install itself.
    case installed(path: AnalyticsUpdateInstallPath, previousVersion: AnalyticsVersion?, previousBuild: Int?,
                   offerVersion: AnalyticsVersion?, offerBuild: Int?, duration: Double?)
    /// DOKK started an install, and the next launch still runs the old build.
    case installFailed(path: AnalyticsUpdateInstallPath, offerVersion: AnalyticsVersion?, offerBuild: Int?,
                       duration: Double?)
    /// Every update error, from Sparkle's engine or from starting the updater.
    case failed(stage: AnalyticsUpdateStage, check: AnalyticsUpdateCheck?, error: AnalyticsUpdateError)
    case releaseNotesFailed(AnalyticsUpdateNotesFailure, error: AnalyticsUpdateError?)
    /// Sparkle finished an update cycle, whatever its result.
    case cycleFinished(AnalyticsUpdateCheck, outcome: AnalyticsUpdateCycleOutcome, error: AnalyticsUpdateError?,
                       duration: Double?)
    case callout(AnalyticsUpdateCalloutAction, kind: UpdateIslandAnnouncement.Kind)
    case whatsNewShown(source: AnalyticsUpdateSource, previousVersion: AnalyticsVersion?)

    var name: String {
        switch self {
        case .opened: "update_opened"
        case .permissionRequested: "update_permission_requested"
        case .checkStarted: "update_check_started"
        case .found: "update_found"
        case .notFound: "update_not_found"
        case .offerShown: "update_offer_shown"
        case .downloadStarted: "update_download_started"
        case .downloadFinished: "update_download_finished"
        case .extracted: "update_extracted"
        case .ready: "update_ready"
        case .action: "update_action"
        case .installStarted: "update_install_started"
        case .installWaitingForQuit: "update_install_waiting_for_quit"
        case .installed: "update_installed"
        case .installFailed: "update_install_failed"
        case .failed: "update_failed"
        case .releaseNotesFailed: "update_release_notes_failed"
        case .cycleFinished: "update_cycle_finished"
        case .callout: "update_callout"
        case .whatsNewShown: "update_whats_new_shown"
        }
    }

    var properties: AnalyticsProperties {
        switch self {
        case let .opened(source, target):
            return ["source": .init(source), "target": .init(target)]
        case .permissionRequested, .installWaitingForQuit:
            return [:]
        case let .checkStarted(check, source):
            return ["check": .init(check), "source": source.map(AnalyticsValue.init)]
        case let .found(check, userInitiated, duration):
            return ["check": check.map(AnalyticsValue.init), "user_initiated": .init(userInitiated),
                    "duration": duration.map(AnalyticsValue.init)]
        case let .notFound(check, reason, latestVersion, latestBuild, userInitiated, duration):
            return ["check": check.map(AnalyticsValue.init), "reason": .init(reason),
                    "latest_version": latestVersion.map(AnalyticsValue.init),
                    "latest_build": latestBuild.map(AnalyticsValue.init),
                    "user_initiated": .init(userInitiated), "duration": duration.map(AnalyticsValue.init)]
        case let .offerShown(stage, userInitiated, presented):
            return ["stage": .init(stage), "user_initiated": .init(userInitiated), "presented": .init(presented)]
        case let .downloadStarted(silent):
            return ["silent": .init(silent)]
        case let .downloadFinished(outcome, silent, duration, expectedBytes, receivedBytes, error):
            return Self.adding(error, to: ["outcome": .init(outcome), "silent": .init(silent),
                "duration": duration.map(AnalyticsValue.init), "expected_bytes": expectedBytes.map(AnalyticsValue.init),
                "received_bytes": receivedBytes.map(AnalyticsValue.init)])
        case let .extracted(silent, duration):
            return ["silent": .init(silent), "duration": duration.map(AnalyticsValue.init)]
        case let .ready(silent, duration):
            return ["silent": .init(silent), "duration": duration.map(AnalyticsValue.init)]
        case let .action(action, via):
            return ["action": .init(action), "via": .init(via)]
        case let .installStarted(path, silent, waited):
            return ["path": .init(path), "silent": .init(silent), "waited": waited.map(AnalyticsValue.init)]
        case let .installed(path, previousVersion, previousBuild, offerVersion, offerBuild, duration):
            return ["path": .init(path), "previous_version": previousVersion.map(AnalyticsValue.init),
                    "previous_build": previousBuild.map(AnalyticsValue.init),
                    "offer_version": offerVersion.map(AnalyticsValue.init),
                    "offer_build": offerBuild.map(AnalyticsValue.init), "duration": duration.map(AnalyticsValue.init)]
        case let .installFailed(path, offerVersion, offerBuild, duration):
            return ["path": .init(path), "offer_version": offerVersion.map(AnalyticsValue.init),
                    "offer_build": offerBuild.map(AnalyticsValue.init), "duration": duration.map(AnalyticsValue.init)]
        case let .failed(stage, check, error):
            return Self.adding(error, to: ["stage": .init(stage), "check": check.map(AnalyticsValue.init)])
        case let .releaseNotesFailed(failure, error):
            return Self.adding(error, to: ["reason": .init(failure)])
        case let .cycleFinished(check, outcome, error, duration):
            return Self.adding(error, to: ["check": .init(check), "outcome": .init(outcome),
                                           "duration": duration.map(AnalyticsValue.init)])
        case let .callout(action, kind):
            return ["action": .init(action), "kind": .init(kind)]
        case let .whatsNewShown(source, previousVersion):
            return ["source": .init(source), "previous_version": previousVersion.map(AnalyticsValue.init)]
        }
    }

    private static func adding(_ error: AnalyticsUpdateError?, to properties: AnalyticsProperties) -> AnalyticsProperties {
        guard let error else { return properties }
        return properties.merging(error.properties)
    }
}

/// State attached to every update event, so each one can be read without the others.
///
/// The `updates_*` settings repeat the registered context on purpose: the context is refreshed
/// a second after a change, and an event sent in between would otherwise carry the old value.
struct AnalyticsUpdateFacts: Equatable {
    var currentVersion: AnalyticsVersion?
    var currentBuild: Int?
    var checksAutomatically: Bool
    var installsAutomatically: Bool
    var installsWhenIdle: Bool
    /// Whether Sparkle permits automatic installs for this app at all.
    var automaticInstallAllowed: Bool
    var phase: UpdatePhase
    var offer: AnalyticsUpdateOffer?

    var properties: AnalyticsProperties {
        var result: AnalyticsProperties = [
            "current_version": currentVersion.map(AnalyticsValue.init),
            "current_build": currentBuild.map(AnalyticsValue.init),
            "updates_check_automatically": .init(checksAutomatically),
            "updates_install_automatically": .init(installsAutomatically),
            "updates_install_when_idle": .init(installsWhenIdle),
            "updates_automatic_install_allowed": .init(automaticInstallAllowed),
            "phase": .init(phase),
        ]
        if let offer { result.merge(offer.properties) }
        return result
    }
}

/// The offer an update event is about, copied from Sparkle's appcast item.
struct AnalyticsUpdateOffer: Equatable {
    var version: AnalyticsVersion?
    var build: Int?
    var critical: Bool
    var major: Bool
    var informational: Bool
    /// True while DOKK holds an update Sparkle downloaded silently.
    var staged: Bool = false
    /// Seconds since a silently downloaded update became ready.
    var stagedFor: Double?

    var properties: AnalyticsProperties {
        ["offer_version": version.map(AnalyticsValue.init), "offer_build": build.map(AnalyticsValue.init),
         "offer_critical": .init(critical), "offer_major": .init(major),
         "offer_informational": .init(informational), "offer_staged": .init(staged),
         "offer_staged_for": stagedFor.map(AnalyticsValue.init)]
    }
}

/// An error reduced to its codes. The message text never leaves the device.
nonisolated struct AnalyticsUpdateError: Equatable, Sendable {
    var code: Int
    var domain: AnalyticsErrorDomain
    var underlyingCode: Int?
    var underlyingDomain: AnalyticsErrorDomain?

    var properties: AnalyticsProperties {
        ["error_code": .init(code), "error_domain": .init(domain),
         "underlying_error_code": underlyingCode.map(AnalyticsValue.init),
         "underlying_error_domain": underlyingDomain.map(AnalyticsValue.init)]
    }
}

nonisolated enum AnalyticsErrorDomain: String, AnalyticsToken, Sendable {
    case sparkle, url, posix, cocoa, osStatus = "os_status", other
}

/// Sparkle's kinds of update check.
nonisolated enum AnalyticsUpdateCheck: String, AnalyticsToken, Sendable {
    /// A check a person started.
    case user
    /// Sparkle's scheduled check.
    case background
    case information
}

/// Where a person asked for the update UI.
nonisolated enum AnalyticsUpdateSource: String, AnalyticsToken, Sendable {
    case menuBar = "menu_bar", appMenu = "app_menu", settings, dockTile = "dock_tile", callout
    /// "Check for Updates" on the What's New page.
    case checkAgain = "check_again"
}

/// What asking for the update UI did.
nonisolated enum AnalyticsUpdateOpenTarget: String, AnalyticsToken, Sendable {
    /// Started a new Sparkle check.
    case newCheck = "new_check"
    /// Brought the running session's panel forward.
    case currentSession = "current_session"
    case whatsNew = "whats_new"
    /// Sparkle could not start a check, for example while it was still busy.
    case unavailable
}

nonisolated enum AnalyticsUpdateNotFoundReason: String, AnalyticsToken, Sendable {
    case unknown, onLatest = "on_latest", onNewer = "on_newer", systemTooOld = "system_too_old"
    case systemTooNew = "system_too_new", hardwareUnsupported = "hardware_unsupported"
}

/// How an update panel action was chosen.
nonisolated enum AnalyticsUpdateActionVia: String, AnalyticsToken, Sendable {
    case button
    /// The panel's close button or Escape. The phase decides which action that stands for.
    case close
    /// Idle install chose Install by itself.
    case idle
}

nonisolated enum AnalyticsUpdateInstallPath: String, AnalyticsToken, Sendable {
    /// Install and Restart in the update panel.
    case user
    case idle
    /// Sparkle installed a prepared update while DOKK quit.
    case onQuit = "on_quit"
    /// Sparkle began installing without a request from DOKK, such as a resumed install.
    case automatic
    /// A new build appeared without DOKK starting an install, for example from a downloaded copy.
    case manual
}

/// Where in the flow an error happened.
nonisolated enum AnalyticsUpdateStage: String, AnalyticsToken, Sendable {
    case startup, check, download, extract, install
}

nonisolated enum AnalyticsUpdateNotesFailure: String, AnalyticsToken, Sendable {
    case download
    /// The notes arrived but were too large or not readable text.
    case decode
    /// The notes could not be turned into the panel's layout.
    case render
    /// The changelog for What's New could not be loaded after an install.
    case whatsNew = "whats_new"
}

nonisolated enum AnalyticsUpdateCycleOutcome: String, AnalyticsToken, Sendable {
    /// Ended without error: installed, dismissed, skipped, or held for a later install.
    case completed
    case noUpdate = "no_update"
    /// The person cancelled the installer's authorization request.
    case canceled
    case failed
}

nonisolated enum AnalyticsUpdateCalloutAction: String, AnalyticsToken, Sendable {
    case shown, opened, dismissed
}
