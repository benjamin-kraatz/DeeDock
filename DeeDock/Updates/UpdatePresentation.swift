#if DIRECT_DISTRIBUTION
import Foundation
import Observation

/// UI-only phases. Sparkle remains authoritative about which operation can run next.
enum UpdatePhase: Equatable {
    case idle, permission, checking, available, downloading, extracting, ready, installing, notFound, failed, installed
}

/// The user-facing facts about an offer, copied before an installer may replace the app bundle.
struct UpdateOffer {
    enum Stage { case notDownloaded, downloaded, installing }
    let version: String
    let stage: Stage
    let critical: Bool
    let major: Bool
    let informational: Bool
    let informationURL: URL?
    let releaseNotesURL: URL?
}

/// Actions carry no Sparkle callbacks; the driver validates their generation before responding.
enum UpdateAction: Hashable {
    case allowChecks, declineChecks, install, skip, later, cancel, hide, retryTermination, done, information
}

/// Observable presentation shared by the window and menu. Constructing it performs no work.
@MainActor
@Observable
final class UpdatePresentation {
    var phase: UpdatePhase = .idle
    var offer: UpdateOffer?
    var receivedBytes: UInt64 = 0
    var expectedBytes: UInt64 = 0
    var extractionProgress: Double?
    var notes: [UpdateReleaseNoteBlock]?
    var loadingNotes = false
    var notesUnavailable = false
    var message: LocalizedStringResource?
    var diagnostic: String?
    var canRetryTermination = false
    /// Invalidates a button rendered for an earlier callback, including queued double-clicks.
    var actionToken = UUID()

    var isActive: Bool { phase != .idle }
    var updateAvailable: Bool { phase == .available || phase == .ready }

    var progress: Double? {
        if phase == .extracting { return extractionProgress }
        guard phase == .downloading, expectedBytes > 0, receivedBytes <= expectedBytes else { return nil }
        return Double(receivedBytes) / Double(expectedBytes)
    }

    var title: LocalizedStringResource {
        switch phase {
        case .idle: .updatesWindowTitle
        case .permission: .updatesPermissionTitle
        case .checking: .updatesCheckingTitle
        case .available: offer?.informational == true ? .updatesInformationTitle : .updatesFoundTitle
        case .downloading: .updatesDownloadingTitle
        case .extracting: .updatesPreparingTitle
        case .ready: .updatesReadyTitle
        case .installing: .updatesInstallingTitle
        case .notFound: .updatesNoUpdateTitle
        case .failed: .updatesFailedTitle
        case .installed: .updatesInstalledTitle
        }
    }

    var summary: LocalizedStringResource {
        if let message { return message }
        switch phase {
        case .permission: return .updatesPermissionBody
        case .checking: return .updatesCheckingBody
        case .available:
            if offer?.informational == true { return .updatesInformationBody }
            if offer?.stage == .installing { return .updatesResumedReadyBody }
            if offer?.stage == .downloaded { return .updatesDownloadedBody }
            return .updatesFoundBody
        case .downloading: return .updatesDownloadingBody
        case .extracting: return .updatesPreparingBody
        case .ready: return .updatesReadyBody
        case .installing: return canRetryTermination ? .updatesWaitingToQuit : .updatesInstallingBody
        case .notFound: return .updatesNoCompatibleUpdate
        case .failed: return .updatesFailureBody
        case .installed: return .updatesInstalledBody
        case .idle: return .updatesAutomaticDescription
        }
    }

    var symbol: String {
        switch phase {
        case .permission: "arrow.trianglehead.2.clockwise"
        case .checking: "magnifyingglass"
        case .available: "arrow.down.circle"
        case .downloading: "arrow.down"
        case .extracting: "shippingbox"
        case .ready, .installing: "arrow.clockwise"
        case .notFound, .installed: "checkmark"
        case .failed: "exclamationmark.triangle"
        case .idle: "dock.rectangle"
        }
    }

    var actions: [UpdateAction] {
        switch phase {
        case .permission: return [.declineChecks, .allowChecks]
        case .checking: return [.cancel]
        case .available:
            if offer?.informational == true {
                return offer?.informationURL == nil ? [.later] : [.later, .information]
            }
            return offer?.critical == true ? [.later, .install] : [.skip, .later, .install]
        case .downloading: return [.cancel, .hide]
        case .extracting: return [.hide]
        case .ready: return [.cancel, .later, .install]
        case .installing: return canRetryTermination ? [.hide, .retryTermination] : [.hide]
        case .notFound, .failed, .installed: return [.done]
        case .idle: return []
        }
    }

    func title(for action: UpdateAction) -> LocalizedStringResource {
        switch action {
        case .allowChecks: .updatesAllowChecks
        case .declineChecks: .updatesManualChecks
        case .install:
            if phase == .ready || offer?.stage == .installing { .updatesInstallRestart }
            else if offer?.stage == .downloaded { .updatesInstall }
            else { .updatesDownload }
        case .skip: offer?.major == true ? .updatesSkipUpgrade : .updatesSkipVersion
        case .later: phase == .ready || offer?.stage == .installing ? .updatesInstallOnQuit : .updatesLater
        case .cancel: .updatesCancel
        case .hide: .updatesHide
        case .retryTermination: .updatesRetryQuit
        case .done: .updatesDone
        case .information: .updatesLearnMore
        }
    }
}
#endif
