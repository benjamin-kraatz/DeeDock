import AppKit
import Sparkle

/// Complete replacement for Sparkle's standard user driver. Reply blocks are consumed before
/// invoking Sparkle because a reply may synchronously deliver the next phase or dismissal.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    let presentation = UpdatePresentation()
    let awareness: UpdateAwarenessStore
    var isWindowVisible: Bool { window.isVisible }
    /// Starts a user-initiated Sparkle check. Used when leaving the installed-version changelog.
    var requestCheck: () -> Void = {}
    /// The island that shows this driver's session, and awareness callouts between sessions.
    var island: UpdateIslandController { window }
    private lazy var window = UpdateIslandController(presentation: presentation, awareness: awareness,
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
        /// Sparkle's immediate-install handler for a silently downloaded update.
        case staged(() -> Void)
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
        transition(.available, response: .choice(reply))
        let stage: UpdateOffer.Stage
        switch state.stage {
        case .downloaded: stage = .downloaded
        case .installing: stage = .installing
        default: stage = .notDownloaded
        }
        adopt(appcastItem, stage: stage, expectsNotesDownload: true)
        awareness.noteWaitingOffer(identity: appcastItem.versionString,
                                   version: appcastItem.displayVersionString,
                                   userInitiated: state.userInitiated)
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
        // A scheduled check that ends without an offer must not close the changelog DOKK
        // opened on its own.
        guard presentation.phase != .whatsNew else { return }
        resetSession()
    }

    /// Returns the window and presentation to idle without answering any Sparkle callback.
    private func resetSession() {
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
        presentation.staged = false
        presentation.message = nil
        presentation.diagnostic = nil
        awareness.noteSessionEnded()
        window.dismiss()
    }

    /// Adopts an update Sparkle downloaded and prepared without any user driver call.
    ///
    /// The automatic driver would otherwise wait for a quit that a dock never gets. The offer
    /// sits at the ready phase so the menu, the callout, and idle install can all finish it
    /// through `install`. Nothing is brought in front of another app.
    func showStagedUpdate(_ appcastItem: SUAppcastItem, install: @escaping () -> Void) {
        transition(.ready, response: .staged(install))
        // Sparkle fetches linked notes only for its own UI flow, so nothing else will arrive.
        adopt(appcastItem, stage: .installing, expectsNotesDownload: false)
        awareness.noteStagedOffer(identity: appcastItem.versionString,
                                  version: appcastItem.displayVersionString)
    }

    #if DEBUG
    /// Puts a made-up staged offer at the ready screen. `install` stands in for Sparkle's handler.
    func debugStage(version: String, install: @escaping () -> Void) {
        notesTask?.cancel()
        comicTask?.cancel()
        transition(.ready, response: .staged(install))
        presentation.offer = UpdateOffer(version: version, stage: .installing, critical: false, major: false,
                                         informational: false, informationURL: nil, releaseNotesURL: nil)
        presentation.comic = nil
        presentation.loadingNotes = false
        presentation.notesUnavailable = false
        presentation.notes = [
            UpdateReleaseNoteBlock(id: 0, style: .heading(2), text: AttributedString("Simulated update")),
            UpdateReleaseNoteBlock(id: 1, text: AttributedString("Nothing is downloaded or installed."), marker: "•")
        ]
    }

    /// Ends a simulated session.
    func debugReset() { resetSession() }
    #endif

    /// Shows the changelog since `previousVersion` after an automatic install.
    /// An active Sparkle session keeps the window; it is shown instead.
    func showWhatsNew(since previousVersion: String) {
        guard !presentation.isActive else { showUpdateInFocus(); return }
        notesTask?.cancel()
        comicTask?.cancel()
        transition(.whatsNew)
        presentation.offer = nil
        presentation.notes = nil
        presentation.notesUnavailable = false
        presentation.comic = nil
        presentation.loadingNotes = true
        let current = presentation.currentVersion
        let german = Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true
        notesTask = Task { [weak self] in
            let notes = await UpdateInstalledNotes.load(after: previousVersion, through: current, german: german)
            guard !Task.isCancelled else { return }
            self?.presentation.notes = notes
            self?.presentation.loadingNotes = false
            self?.presentation.notesUnavailable = notes == nil
        }
        if let relatedURL = UpdateComicResourcePolicy.notesURL(version: current) {
            loadComic(from: relatedURL)
        }
        window.present(activate: true)
    }

    func showUpdateInFocus() {
        guard presentation.isActive else { return }
        awareness.noteWindowOpened()
        window.present(activate: true)
    }

    /// One idle-install attempt. No-ops when the ready reply is no longer valid.
    func attemptIdleInstall() {
        guard presentation.phase == .ready, presentation.actions.contains(.install) else { return }
        // Written before the bundle is replaced so the next launch can announce the update.
        awareness.recordAutomaticInstall()
        perform(.install, token: presentation.actionToken)
    }

    /// Called only at process termination. Does not synthesize an install/skip reply.
    func stop() {
        resetSession()
        window.stop()
    }

    private func transition(_ phase: UpdatePhase, response: Response? = nil) {
        self.response = response
        presentation.actionToken = UUID()
        presentation.phase = phase
        presentation.message = nil
        presentation.diagnostic = nil
        presentation.canRetryTermination = false
        if case .staged = response { presentation.staged = true } else { presentation.staged = false }
    }

    /// Copies the offer's user-facing facts and starts loading its embedded notes and comic.
    /// - Parameter expectsNotesDownload: Whether Sparkle will deliver linked release notes later.
    private func adopt(_ appcastItem: SUAppcastItem, stage: UpdateOffer.Stage, expectsNotesDownload: Bool) {
        notesTask?.cancel()
        comicTask?.cancel()
        presentation.offer = UpdateOffer(version: appcastItem.displayVersionString,
            identity: appcastItem.versionString, stage: stage,
            critical: appcastItem.isCriticalUpdate, major: appcastItem.isMajorUpgrade,
            informational: appcastItem.isInformationOnlyUpdate,
            informationURL: UpdateReleaseNotes.safeLink(appcastItem.infoURL),
            releaseNotesURL: UpdateReleaseNotes.safeLink(appcastItem.releaseNotesURL))
        presentation.notes = nil
        presentation.notesUnavailable = false
        presentation.comic = nil
        presentation.loadingNotes = expectsNotesDownload && appcastItem.releaseNotesURL != nil
        if let text = appcastItem.itemDescription, !text.isEmpty {
            loadNotes(text, format: appcastItem.itemDescriptionFormat ?? "html")
        }
        if let relatedURL = UpdateReleaseNotes.safeLink(appcastItem.releaseNotesURL)
            ?? UpdateReleaseNotes.safeLink(appcastItem.fileURL) {
            loadComic(from: relatedURL)
        }
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
        if presentation.phase == .whatsNew, action == .done || action == .checkAgain {
            // No Sparkle callback backs this phase. Return to idle before a new check starts.
            resetSession()
            if action == .checkAgain { requestCheck() }
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
        case (.staged(let install), .install):
            // Sparkle relaunches without further driver calls. If termination is refused the
            // update still installs on quit.
            transition(.installing)
            install()
        case (.staged, .later):
            // The update stays prepared for idle install, a later click, or quit.
            self.response = response
            window.dismiss()
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
        case .failed, .notFound, .installed, .whatsNew: action = .done
        default: window.dismiss(); return
        }
        perform(action, token: presentation.actionToken)
    }
}
