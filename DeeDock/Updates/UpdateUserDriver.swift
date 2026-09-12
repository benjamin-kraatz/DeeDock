#if DIRECT_DISTRIBUTION
import AppKit
import Sparkle

/// Complete replacement for Sparkle's standard user driver. Reply blocks are consumed before
/// invoking Sparkle because a reply may synchronously deliver the next phase or dismissal.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    let presentation = UpdatePresentation()
    let awareness: UpdateAwarenessStore
    var isWindowVisible: Bool { window.isVisible }
    // Cache artwork before the app bundle can be replaced by an installation.
    private let icon = NSImage(named: NSImage.applicationIconName)
    private lazy var window = UpdateWindowController(presentation: presentation, awareness: awareness, icon: icon,
        action: { [weak self] action, token in self?.perform(action, token: token) },
        close: { [weak self] in self?.closeWindow() })

    init(awareness: UpdateAwarenessStore) {
        self.awareness = awareness
        super.init()
    }

    private enum Response {
        case permission((SUUpdatePermissionResponse) -> Void)
        case choice((SPUUserUpdateChoice) -> Void)
        case cancellation(() -> Void)
        case acknowledgement(() -> Void)
        case termination(() -> Void)
    }
    private var response: Response?
    private var notesTask: Task<Void, Never>?
    private var comicTask: Task<Void, Never>?

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        transition(.permission, response: .permission(reply))
        window.present(activate: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        transition(.checking, response: .cancellation(cancellation))
        window.present(activate: true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        notesTask?.cancel()
        comicTask?.cancel()
        transition(.available, response: .choice(reply))
        let stage: UpdateOffer.Stage
        switch state.stage {
        case .downloaded: stage = .downloaded
        case .installing: stage = .installing
        default: stage = .notDownloaded
        }
        presentation.offer = UpdateOffer(version: appcastItem.displayVersionString,
            identity: appcastItem.versionString, stage: stage,
            critical: appcastItem.isCriticalUpdate, major: appcastItem.isMajorUpgrade,
            informational: appcastItem.isInformationOnlyUpdate,
            informationURL: UpdateReleaseNotes.safeLink(appcastItem.infoURL),
            releaseNotesURL: UpdateReleaseNotes.safeLink(appcastItem.releaseNotesURL))
        awareness.noteWaitingOffer(identity: appcastItem.versionString,
                                   version: appcastItem.displayVersionString,
                                   userInitiated: state.userInitiated)
        presentation.notes = nil
        presentation.notesUnavailable = false
        presentation.comic = nil
        presentation.loadingNotes = appcastItem.releaseNotesURL != nil
        if let text = appcastItem.itemDescription, !text.isEmpty {
            loadNotes(text, format: appcastItem.itemDescriptionFormat ?? "html")
        }
        if let relatedURL = UpdateReleaseNotes.safeLink(appcastItem.releaseNotesURL)
            ?? UpdateReleaseNotes.safeLink(appcastItem.fileURL) {
            loadComic(from: relatedURL)
        }
        // A scheduled offer is retained for the menu, never brought in front of another app.
        if state.userInitiated {
            awareness.noteWindowOpened()
            window.present(activate: true)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard presentation.offer != nil else { return }
        guard downloadData.data.count <= UpdateReleaseNotes.maximumBytes,
              let text = UpdateReleaseNotes.decode(downloadData.data, encodingName: downloadData.textEncodingName) else {
            presentation.loadingNotes = false
            presentation.notesUnavailable = true
            return
        }
        loadNotes(text, format: downloadData.mimeType ?? "text/plain")
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        notesTask?.cancel()
        presentation.loadingNotes = false
        presentation.notesUnavailable = true
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        transition(.notFound, response: .acknowledgement(acknowledgement))
        let error = error as NSError
        if let value = error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber {
            switch SPUNoUpdateFoundReason(rawValue: value.int32Value) {
            case .onLatestVersion:
                presentation.message = .updatesOnLatest(currentVersion: presentation.currentVersion)
            case .onNewerThanLatestVersion:
                presentation.message = .updatesOnNewer(currentVersion: presentation.currentVersion)
            case .systemIsTooOld, .systemIsTooNew: presentation.message = .updatesOSIncompatible
            case .hardwareDoesNotSupportARM64: presentation.message = .updatesHardwareIncompatible
            default: presentation.message = .updatesNoCompatibleUpdate
            }
        }
        window.present(activate: true)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        transition(.failed, response: .acknowledgement(acknowledgement))
        let error = error as NSError
        presentation.diagnostic = [error.localizedDescription, error.localizedFailureReason,
                                   error.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        window.present(activate: false)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        transition(.downloading, response: .cancellation(cancellation))
        presentation.receivedBytes = 0
        presentation.expectedBytes = 0
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard presentation.phase == .downloading else { return }
        presentation.expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard presentation.phase == .downloading else { return }
        let (total, overflow) = presentation.receivedBytes.addingReportingOverflow(length)
        presentation.receivedBytes = overflow ? UInt64.max : total
    }

    func showDownloadDidStartExtractingUpdate() {
        // Download cancellation is no longer valid once extraction begins.
        transition(.extracting)
        presentation.extractionProgress = nil
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        guard presentation.phase == .extracting else { return }
        presentation.extractionProgress = progress.isFinite ? min(max(progress, 0), 1) : nil
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        transition(.ready, response: .choice(reply))
        if let offer = presentation.offer, !offer.informational {
            awareness.noteWaitingOffer(identity: offer.identity, version: offer.version, userInitiated: false)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) {
        transition(.installing, response: applicationTerminated ? nil : .termination(retryTerminatingApplication))
        presentation.canRetryTermination = !applicationTerminated
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        // The old app bundle may have been replaced. No bundle or icon reads occur here.
        transition(.installed, response: .acknowledgement(acknowledgement))
        window.present(activate: false)
    }

    func dismissUpdateInstallation() {
        notesTask?.cancel()
        notesTask = nil
        comicTask?.cancel()
        comicTask = nil
        response = nil
        presentation.phase = .idle
        presentation.actionToken = UUID()
        presentation.offer = nil
        presentation.notes = nil
        presentation.comic = nil
        presentation.loadingNotes = false
        presentation.notesUnavailable = false
        presentation.receivedBytes = 0
        presentation.expectedBytes = 0
        presentation.extractionProgress = nil
        presentation.canRetryTermination = false
        presentation.message = nil
        presentation.diagnostic = nil
        awareness.noteSessionEnded()
        window.dismiss()
    }

    func showUpdateInFocus() {
        guard presentation.isActive else { return }
        if presentation.updateAvailable { awareness.noteWindowOpened() }
        window.present(activate: true)
    }

    /// One idle-install attempt. No-ops when the ready reply is no longer valid.
    func attemptIdleInstall() {
        guard presentation.phase == .ready, presentation.actions.contains(.install) else { return }
        perform(.install, token: presentation.actionToken)
    }

    /// Called only at process termination. Does not synthesize an install/skip reply.
    func stop() {
        dismissUpdateInstallation()
        window.stop()
    }

    private func transition(_ phase: UpdatePhase, response: Response? = nil) {
        self.response = response
        presentation.actionToken = UUID()
        presentation.phase = phase
        presentation.message = nil
        presentation.diagnostic = nil
        presentation.canRetryTermination = false
    }

    private func loadNotes(_ text: String, format: String) {
        notesTask?.cancel()
        presentation.loadingNotes = true
        notesTask = Task { [weak self] in
            let notes = await UpdateReleaseNotes.render(text, format: format)
            guard !Task.isCancelled else { return }
            self?.presentation.notes = notes
            self?.presentation.loadingNotes = false
            self?.presentation.notesUnavailable = notes == nil
        }
    }

    /// Quiet companion fetch. A miss leaves the existing notes layout unchanged.
    private func loadComic(from relatedURL: URL) {
        comicTask?.cancel()
        comicTask = Task { [weak self] in
            let comic = await UpdateComicLoader.load(fromRelatedURL: relatedURL)
            guard !Task.isCancelled else { return }
            self?.presentation.comic = comic
        }
    }

    private func perform(_ action: UpdateAction, token: UUID) {
        guard token == presentation.actionToken, presentation.actions.contains(action) else { return }
        if action == .hide { window.dismiss(); return }
        if action == .information {
            if let url = presentation.offer?.informationURL { NSWorkspace.shared.open(url) }
            return
        }
        guard let response else { return }
        // Invalidate the rendered action before calling any client callback.
        self.response = nil
        presentation.actionToken = UUID()
        switch (response, action) {
        case (.permission(let reply), .allowChecks), (.permission(let reply), .declineChecks):
            dismissUpdateInstallation()
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: action == .allowChecks,
                                             sendSystemProfile: false))
        case (.choice(let reply), .install):
            // Installing an already-prepared offer may immediately restart the app.
            transition(presentation.phase == .ready || presentation.offer?.stage == .installing ? .installing : .extracting)
            reply(.install)
        case (.choice(let reply), .skip):
            dismissUpdateInstallation()
            reply(.skip)
        case (.choice(let reply), .later):
            dismissUpdateInstallation()
            reply(.dismiss)
        case (.choice(let reply), .cancel):
            dismissUpdateInstallation()
            reply(.skip) // At ready-to-install, skip cancels this installation without skipping the version.
        case (.cancellation(let cancel), .cancel):
            dismissUpdateInstallation()
            cancel()
        case (.acknowledgement(let acknowledge), .done):
            dismissUpdateInstallation()
            acknowledge()
        case (.termination(let retry), .retryTermination):
            self.response = response // Sparkle explicitly permits retrying termination more than once.
            retry()
        default:
            self.response = response
        }
    }

    private func closeWindow() {
        let action: UpdateAction
        switch presentation.phase {
        case .permission: action = .declineChecks
        case .checking: action = .cancel
        case .available, .ready: action = .later
        case .failed, .notFound, .installed: action = .done
        default: window.dismiss(); return
        }
        perform(action, token: presentation.actionToken)
    }
}
#endif
