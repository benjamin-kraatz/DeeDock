import Foundation
import Sparkle

/// Turns the update flow into `update_*` analytics events.
///
/// Owned by ``AppUpdater``. Three callers report to it: ``UpdateEngineDelegate``, which sees
/// every Sparkle cycle including silent downloads; ``UpdateUserDriver``, which sees what a person
/// is shown and chooses; and ``UpdateIslandController`` for callouts. Every event carries
/// ``AnalyticsUpdateFacts`` from ``snapshot`` and the offer this type remembers.
///
/// It keeps only what durations and the install path need. One record is persisted right
/// before an install, so the next launch reports whether it completed.
@MainActor
final class UpdateAnalytics {
    /// Live settings and presentation state, read for each event. Set by ``AppUpdater``.
    var snapshot: () -> Snapshot = { Snapshot() }

    struct Snapshot {
        var checksAutomatically = false
        var installsAutomatically = false
        var installsWhenIdle = false
        var automaticInstallAllowed = false
        var phase: UpdatePhase = .idle
        /// DOKK holds an update Sparkle downloaded silently.
        var staged = false
        var stagedSince: Date?
        var expectedBytes: UInt64 = 0
        var receivedBytes: UInt64 = 0
    }

    private let send: (AnalyticsEvent) -> Void
    /// Nil reads ``Analytics/acceptsEvents`` at launch. Tests pass a fixed value.
    private let analyticsEnabledOverride: Bool?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let currentVersion: String
    private let currentBuild: String?

    /// Source of the next user-initiated check, consumed when Sparkle starts it.
    private var pendingSource: AnalyticsUpdateSource?
    private var check: AnalyticsUpdateCheck?
    private var checkStartedAt: Date?
    private var offer: AnalyticsUpdateOffer?
    private var offerIdentity: (version: String?, build: String?)
    /// The custom driver showed this cycle's offer, so downloads and installs are not silent.
    private var interactive = false
    private var downloadStartedAt: Date?
    private var extractStartedAt: Date?
    private var readyAt: Date?
    private var stage: AnalyticsUpdateStage = .check
    /// Set by the action that asked for the install, read when it starts.
    private var installPath: AnalyticsUpdateInstallPath?
    /// "Install on Quit" ended the panel session but left Sparkle's prepared install in place.
    private var heldForQuit = false
    private var installReported = false

    /// - Parameters:
    ///   - currentVersion: The running marketing version. Nil reads version and build from the bundle.
    ///   - currentBuild: The running build, used only with an explicit `currentVersion`.
    ///   - analyticsEnabled: Whether `Application updated` may be handed over. Nil reads
    ///     ``Analytics/acceptsEvents`` when the launch is reported. The version is stored either way.
    ///   - send: Receives each event. Nil sends through ``Analytics/track(_:)``; tests pass a recorder.
    init(defaults: UserDefaults = .standard, currentVersion: String? = nil, currentBuild: String? = nil,
         now: @escaping () -> Date = Date.init, analyticsEnabled: Bool? = nil,
         send: ((AnalyticsEvent) -> Void)? = nil) {
        self.defaults = defaults
        self.now = now
        self.analyticsEnabledOverride = analyticsEnabled
        self.send = send ?? { Analytics.track($0) }
        self.currentVersion = currentVersion ?? AppVersionInfo.current.version
        self.currentBuild = currentVersion == nil ? AppVersionInfo.current.build : currentBuild
    }

    // MARK: - Launch and termination

    /// Reports an install that finished or failed since the last launch, then records this one.
    ///
    /// Call once at launch. The first launch stores the version and sends no `Application updated`.
    /// A later launch sends it only when the version or build changed and analytics is accepting
    /// events. The stored version is written after that hand-off, so a crash before the hand-off
    /// is reported again on the next launch.
    func reportLaunch() {
        let previous = UpdateLaunchRecord.load(from: defaults)
        let pending = UpdatePendingInstallRecord.load(from: defaults)
        // The marker belongs to the offered target only. Any other launch drops it.
        let updateSource: ApplicationUpdateSource?
        if let pending {
            let path = AnalyticsUpdateInstallPath(rawValue: pending.path) ?? .automatic
            let duration = now().timeIntervalSince(pending.startedAt)
            if pending.matchesTarget(version: currentVersion, build: currentBuild) {
                updateSource = pending.updateSource.flatMap(ApplicationUpdateSource.init(rawValue:))
                emit(.installed(path: path, previousVersion: AnalyticsVersion(pending.fromVersion),
                                previousBuild: AnalyticsVersion.build(pending.fromBuild),
                                offerVersion: AnalyticsVersion(pending.offerVersion),
                                offerBuild: AnalyticsVersion.build(pending.offerBuild), duration: duration))
            } else if pending.isSameBuild(version: currentVersion, build: currentBuild),
                      pending.offerVersion != nil, pending.offerBuild != nil {
                // Still the build that started the install, and the offer was a different build.
                // A cancelled attempt never reaches here: `aborted` already removed the record.
                updateSource = nil
                emit(.installFailed(path: path, offerVersion: AnalyticsVersion(pending.offerVersion),
                                    offerBuild: AnalyticsVersion.build(pending.offerBuild), duration: duration))
            } else {
                updateSource = nil
                if let previous, previous.version != currentVersion || previous.build != currentBuild {
                    emit(.installed(path: .manual, previousVersion: AnalyticsVersion(previous.version),
                                    previousBuild: AnalyticsVersion.build(previous.build),
                                    offerVersion: nil, offerBuild: nil, duration: nil))
                }
            }
            UpdatePendingInstallRecord.clear(in: defaults)
        } else {
            updateSource = nil
            if let previous, previous.version != currentVersion || previous.build != currentBuild {
                emit(.installed(path: .manual, previousVersion: AnalyticsVersion(previous.version),
                                previousBuild: AnalyticsVersion.build(previous.build),
                                offerVersion: nil, offerBuild: nil, duration: nil))
            }
        }
        if let change = ApplicationUpdateLaunch.change(
            from: previous.map { .init(version: $0.version, build: $0.build) },
            to: .init(version: currentVersion, build: currentBuild),
            analyticsEnabled: analyticsEnabledOverride ?? Analytics.shared.acceptsEvents,
            updateSource: updateSource,
            channel: AnalyticsChannel.current
        ) {
            send(.applicationUpdated(change))
        }
        UpdateLaunchRecord(version: currentVersion, build: currentBuild).save(to: defaults)
    }

    /// Call from termination before the driver resets. A prepared update that DOKK still holds,
    /// or one left for "Install on Quit", is installed by Sparkle as DOKK quits.
    func reportTermination() {
        // An offer is adopted for every real Sparkle update; the debug simulation has none.
        guard !installReported, offer != nil, snapshot().phase == .ready || heldForQuit else { return }
        beginInstall(path: .onQuit)
    }

    // MARK: - Entry points

    /// A person asked for the update UI. `target` says what that did.
    func opened(_ source: AnalyticsUpdateSource, target: AnalyticsUpdateOpenTarget) {
        if target == .newCheck { pendingSource = source }
        emit(.opened(source: source, target: target))
    }

    func whatsNewShown(source: AnalyticsUpdateSource, previousVersion: String) {
        emit(.whatsNewShown(source: source, previousVersion: AnalyticsVersion(previousVersion)))
    }

    func callout(_ action: AnalyticsUpdateCalloutAction, kind: UpdateIslandAnnouncement.Kind) {
        emit(.callout(action, kind: kind))
    }

    // MARK: - Sparkle engine

    func checkStarted(_ updateCheck: SPUUpdateCheck) {
        let check = Self.check(updateCheck)
        self.check = check
        checkStartedAt = now()
        offer = nil
        offerIdentity = (nil, nil)
        interactive = false
        downloadStartedAt = nil
        extractStartedAt = nil
        readyAt = nil
        installPath = nil
        installReported = false
        heldForQuit = false
        stage = .check
        let source = check == .user ? pendingSource : nil
        pendingSource = nil
        emit(.checkStarted(check, source: source))
    }

    func found(_ item: SUAppcastItem) {
        adopt(item)
        emit(.found(check, userInitiated: check == .user, duration: elapsed(since: checkStartedAt)))
    }

    func notFound(_ error: Error) {
        let info = (error as NSError).userInfo
        let latest = info[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        let userInitiated = (info[SPUNoUpdateFoundUserInitiatedKey] as? NSNumber)?.boolValue ?? (check == .user)
        emit(.notFound(check, reason: Self.reason(info[SPUNoUpdateFoundReasonKey] as? NSNumber),
                       latestVersion: AnalyticsVersion(latest?.displayVersionString),
                       latestBuild: AnalyticsVersion.build(latest?.versionString),
                       userInitiated: userInitiated, duration: elapsed(since: checkStartedAt)))
    }

    func downloadStarted(_ item: SUAppcastItem) {
        adopt(item)
        stage = .download
        downloadStartedAt = now()
        emit(.downloadStarted(silent: !interactive))
    }

    func downloadFinished(_ outcome: AnalyticsOutcome, error: Error? = nil) {
        let state = snapshot()
        let showsBytes = interactive && state.expectedBytes > 0
        emit(.downloadFinished(outcome, silent: !interactive, duration: elapsed(since: downloadStartedAt),
                               expectedBytes: showsBytes ? Self.int(state.expectedBytes) : nil,
                               receivedBytes: showsBytes ? Self.int(state.receivedBytes) : nil,
                               error: error.map(Self.error)))
    }

    func extractionStarted() {
        stage = .extract
        extractStartedAt = now()
    }

    func extracted() {
        emit(.extracted(silent: !interactive, duration: elapsed(since: extractStartedAt)))
    }

    /// Sparkle is about to install. Also reached for an install DOKK did not request.
    func installStarted(_ item: SUAppcastItem) {
        adopt(item)
        guard !installReported else { return }
        beginInstall(path: installPath ?? .automatic)
    }

    /// Every error that ends a Sparkle cycle except "no update" and a cancelled installer prompt.
    /// "No update" is reported by ``notFound(_:)``.
    ///
    /// The pending record is written before the authorization dialog, so every abort removes it,
    /// including "no update" and Sparkle `4007`. A cancelled attempt must not be read on a later launch.
    func aborted(_ error: Error) {
        UpdatePendingInstallRecord.clear(in: defaults)
        let error = Self.error(error)
        // "No update" and a cancelled installer prompt share this callback with real failures.
        // Leaving them out keeps `update_failed` usable as a success-rate denominator.
        guard !Self.isExcludedFailure(error) else { return }
        emit(.failed(stage: stage, check: check, error: error))
    }

    func startupFailed(_ error: Error) {
        emit(.failed(stage: .startup, check: nil, error: Self.error(error)))
    }

    func cycleFinished(_ updateCheck: SPUUpdateCheck, error: Error?) {
        let converted = error.map(Self.error)
        let outcome: AnalyticsUpdateCycleOutcome
        switch converted {
        case nil: outcome = .completed
        case let error? where error.domain == .sparkle && error.code == Int(SUError.noUpdateError.rawValue):
            outcome = .noUpdate
        case let error? where error.domain == .sparkle && error.code == Int(SUError.installationCanceledError.rawValue):
            outcome = .canceled
        default: outcome = .failed
        }
        emit(.cycleFinished(Self.check(updateCheck), outcome: outcome, error: converted,
                            duration: elapsed(since: checkStartedAt)))
    }

    // MARK: - User driver

    func permissionRequested() {
        emit(.permissionRequested)
    }

    func offerShown(_ item: SUAppcastItem, stage: UpdateOffer.Stage, userInitiated: Bool) {
        adopt(item)
        interactive = true
        // A resumed install is already prepared. Unless skipped, Sparkle installs it on quit.
        if stage == .installing { heldForQuit = true }
        emit(.offerShown(stage: stage, userInitiated: userInitiated, presented: userInitiated))
    }

    /// The update is prepared. `item` is passed for a silent download DOKK adopts.
    func ready(silent: Bool, item: SUAppcastItem? = nil) {
        if let item { adopt(item) }
        stage = .install
        readyAt = now()
        emit(.ready(silent: silent, duration: elapsed(since: downloadStartedAt)))
    }

    /// Call after the driver accepted the action and before it answers Sparkle, so the event
    /// carries the phase the person acted in.
    func action(_ action: UpdateAction, via: AnalyticsUpdateActionVia) {
        let state = snapshot()
        emit(.action(action, via: via))
        switch action {
        case .install:
            installPath = via == .idle ? .idle : .user
            stage = state.phase == .available ? .download : .install
        case .later:
            // At the ready step Sparkle keeps the prepared update and installs it on quit.
            if state.phase == .ready, !state.staged { heldForQuit = true }
        case .skip, .cancel:
            heldForQuit = false
        default:
            break
        }
    }

    func installWaitingForQuit() {
        emit(.installWaitingForQuit)
    }

    func releaseNotesFailed(_ failure: AnalyticsUpdateNotesFailure, error: Error? = nil) {
        emit(.releaseNotesFailed(failure, error: error.map(Self.error)))
    }

    // MARK: - Helpers

    private func beginInstall(path: AnalyticsUpdateInstallPath) {
        installReported = true
        UpdatePendingInstallRecord(fromVersion: currentVersion, fromBuild: currentBuild,
                                   offerVersion: offerIdentity.version, offerBuild: offerIdentity.build,
                                   path: path.rawValue,
                                   updateSource: check.flatMap { ApplicationUpdateSource($0)?.rawValue },
                                   startedAt: now())
            .save(to: defaults)
        emit(.installStarted(path: path, silent: !interactive, waited: elapsed(since: readyAt)))
    }

    private func adopt(_ item: SUAppcastItem) {
        offerIdentity = (item.displayVersionString, item.versionString)
        offer = AnalyticsUpdateOffer(version: AnalyticsVersion(item.displayVersionString),
                                     build: AnalyticsVersion.build(item.versionString),
                                     critical: item.isCriticalUpdate, major: item.isMajorUpgrade,
                                     informational: item.isInformationOnlyUpdate)
    }

    private func emit(_ event: AnalyticsUpdateEvent) {
        send(.update(event, facts()))
    }

    private func facts() -> AnalyticsUpdateFacts {
        let state = snapshot()
        var offer = offer
        offer?.staged = state.staged
        offer?.stagedFor = state.staged ? elapsed(since: state.stagedSince) : nil
        return AnalyticsUpdateFacts(
            currentVersion: AnalyticsVersion(currentVersion), currentBuild: AnalyticsVersion.build(currentBuild),
            checksAutomatically: state.checksAutomatically, installsAutomatically: state.installsAutomatically,
            installsWhenIdle: state.installsWhenIdle, automaticInstallAllowed: state.automaticInstallAllowed,
            phase: state.phase, offer: offer)
    }

    private func elapsed(since start: Date?) -> Double? {
        start.map { max(0, now().timeIntervalSince($0)) }
    }

    private static func int(_ value: UInt64) -> Int {
        Int(clamping: value)
    }

    private static func check(_ check: SPUUpdateCheck) -> AnalyticsUpdateCheck {
        switch check {
        case .updates: .user
        case .updatesInBackground: .background
        case .updateInformation: .information
        @unknown default: .background
        }
    }

    private static func reason(_ value: NSNumber?) -> AnalyticsUpdateNotFoundReason {
        guard let value else { return .unknown }
        switch SPUNoUpdateFoundReason(rawValue: value.int32Value) {
        case .onLatestVersion: return .onLatest
        case .onNewerThanLatestVersion: return .onNewer
        case .systemIsTooOld: return .systemTooOld
        case .systemIsTooNew: return .systemTooNew
        case .hardwareDoesNotSupportARM64: return .hardwareUnsupported
        default: return .unknown
        }
    }

    /// "No update" and the person cancelling the installer's authorization prompt.
    private static func isExcludedFailure(_ error: AnalyticsUpdateError) -> Bool {
        guard error.domain == .sparkle else { return false }
        return error.code == Int(SUError.noUpdateError.rawValue)
            || error.code == Int(SUError.installationCanceledError.rawValue)
    }

    /// Keeps the codes and drops the message, which may contain paths or URLs.
    static func error(_ error: Error) -> AnalyticsUpdateError {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return AnalyticsUpdateError(code: error.code, domain: domain(error.domain),
                                    underlyingCode: underlying?.code, underlyingDomain: underlying.map { domain($0.domain) })
    }

    private static func domain(_ domain: String) -> AnalyticsErrorDomain {
        switch domain {
        case SUSparkleErrorDomain: .sparkle
        case NSURLErrorDomain: .url
        case NSPOSIXErrorDomain: .posix
        case NSCocoaErrorDomain: .cocoa
        case NSOSStatusErrorDomain: .osStatus
        default: .other
        }
    }
}
