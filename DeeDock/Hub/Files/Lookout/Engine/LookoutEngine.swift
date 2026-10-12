import Foundation
import Observation
import os

/// Lookout's app-side engine: the composition point of the settings, the index service, the query encoder, the
/// index reader, the folder and system monitors and the power policy. `status` drives the UI.
///
/// One engine exists for the app's lifetime (`HubCoordinator` makes it); it runs while the app runs, whether or not
/// the Hub is open, so new files get indexed. It does nothing until Lookout is set up and turned on, and never under
/// the test host or in previews (`live()` returns an inert engine there).
///
/// The index service exits by itself when idle. The engine wakes it on demand: FSEvents changes (debounced
/// `syncDebounce`), a drive mounted or ejected, wake from sleep, a settings change, the model arriving, the backfill
/// becoming allowed, and `resume()`. The connection replays the configuration and pause state to a relaunched
/// service (`LookoutIndexControlling`).
///
/// Memory: the query encoder is warmed when the Files tab appears; its service exits 120 s after its last call. Its
/// picture reader loads only for a search with a picture, or when a picture is dragged over the Hub. The
/// in-memory vectors are released `vectorReleaseDelay` after the Files tab hides or the Hub closes, and load again for
/// the next search.
///
/// `progress` follows every status the service sends, but changes at most every `progressInterval` while files go
/// by (a phase change shows at once); a trailing publish makes sure the last status always shows. Nothing polls.
///
/// Main actor. The owned tasks (the sync debounce, the vector release, the warm-up, the trailing progress publish)
/// are cancelled when they're replaced and in `stop()`. Calls into the reader actor are short one-way hops that own
/// nothing; the actor orders them.
@MainActor @Observable
final class LookoutEngine {
    /// FSEvents changes settle this long before a sync (a copy in progress, a burst of screenshots).
    nonisolated static let syncDebounce: Duration = .seconds(2)
    /// How long the vectors stay in memory after the Files tab hides or the Hub closes.
    nonisolated static let vectorReleaseDelay: Duration = .seconds(120)
    /// The shortest time between two changes of `progress` while the phase stays the same: twice a second.
    nonisolated static let progressInterval: Duration = .milliseconds(500)

    /// What the UI shows.
    private(set) var status: LookoutStatus = .notSetUp
    private(set) var settings: LookoutSettings
    /// The index service's latest status, while running: counts, progress, the current file.
    private(set) var indexStatus: LookoutIndexStatus?
    /// Where reading stands, for Settings' progress card and the Files tab's status chip (`LookoutProgressTracker`).
    /// Nil while Lookout isn't set up, is off, or waits for the model.
    private(set) var progress: LookoutProgressDisplay?
    /// True between `start()` and `stop()` while Lookout is active.
    private(set) var isRunning = false
    /// Lookout's content search; phase 2's Files UI shows it beside the name search.
    let search: LookoutSearch
    /// Searching with a picture or with a file's stored vector (Find Similar).
    let pictureSearch: LookoutPictureSearch

    /// Chosen folders that aren't there right now (an unplugged drive). Their files stay indexed.
    var missingFolders: [String] { indexStatus?.missingRoots ?? [] }
    /// Chosen folders macOS won't let Lookout read (Privacy & Security → Files and Folders).
    var notPermittedFolders: [String] { indexStatus?.notPermittedRoots ?? [] }

    @ObservationIgnored private let repository: LookoutSettingsRepository?
    @ObservationIgnored private let connection: any LookoutIndexControlling
    @ObservationIgnored private let encoder: any LookoutQueryEncoding
    @ObservationIgnored private let reader: any LookoutIndexSearching
    @ObservationIgnored private let monitor: any LookoutMonitoring
    @ObservationIgnored private let power: any LookoutPowerPolicing
    /// Where the index and the models live.
    @ObservationIgnored let paths: LookoutPaths
    @ObservationIgnored private let canRun: Bool
    @ObservationIgnored private let syncDebounce: Duration
    @ObservationIgnored private let releaseDelay: Duration

    @ObservationIgnored private var userPaused = false
    @ObservationIgnored private var serviceUnavailable = false
    @ObservationIgnored private var blocker: LookoutBackfillBlocker?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var progressTracker = LookoutProgressTracker()
    @ObservationIgnored private let progressInterval: Duration
    @ObservationIgnored private let now: () -> Date
    /// When `progress` last changed, and the newer progress waiting for `progressInterval` to pass.
    @ObservationIgnored private var progressPublishedAt: ContinuousClock.Instant?
    @ObservationIgnored private var pendingProgress: LookoutProgressDisplay??
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    /// - Parameters:
    ///   - settings: The settings to start with (usually `repository.loadOrDefault()`).
    ///   - repository: Where `apply` saves settings; nil never saves.
    ///   - canRun: False for an engine that must never start (previews, tests of the UI).
    ///   - syncDebounce: The FSEvents debounce; tests shorten it.
    ///   - releaseDelay: The vector release delay; tests shorten it.
    ///   - progressInterval: The progress throttle; tests shorten it.
    ///   - now: The clock the progress's pace is measured with; tests pass their own.
    init(settings: LookoutSettings, repository: LookoutSettingsRepository?, connection: any LookoutIndexControlling,
         encoder: any LookoutQueryEncoding, reader: any LookoutIndexSearching, monitor: any LookoutMonitoring,
         power: any LookoutPowerPolicing, paths: LookoutPaths, canRun: Bool,
         syncDebounce: Duration = LookoutEngine.syncDebounce,
         releaseDelay: Duration = LookoutEngine.vectorReleaseDelay,
         progressInterval: Duration = LookoutEngine.progressInterval,
         now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.repository = repository
        self.connection = connection
        self.encoder = encoder
        self.reader = reader
        self.monitor = monitor
        self.power = power
        self.paths = paths
        self.canRun = canRun
        self.syncDebounce = syncDebounce
        self.releaseDelay = releaseDelay
        self.progressInterval = progressInterval
        self.now = now
        search = LookoutSearch(reader: reader, encoder: encoder)
        pictureSearch = LookoutPictureSearch(reader: reader, encoder: encoder)
        updateStatus()
    }

    /// The real engine: XPC services embedded in DOKK.app, `~/Library/Application Support/DDock/Lookout`, and the
    /// settings in the standard defaults. Inert under the test host, in previews, and without a bundle identifier.
    static func live() -> LookoutEngine {
        guard !HostEnvironment.isTestHost, !HostEnvironment.isPreview,
              let bundleID = Bundle.main.bundleIdentifier else { return inert() }
        let repository = LookoutSettingsRepository(defaults: .standard)
        let paths = LookoutPaths.standard
        return LookoutEngine(
            settings: repository.loadOrDefault(), repository: repository,
            connection: LookoutIndexConnection(serviceName: LookoutServiceNames.index(appBundleIdentifier: bundleID)),
            encoder: LookoutQueryEncoder(serviceName: LookoutServiceNames.query(appBundleIdentifier: bundleID)),
            reader: LookoutIndexReader(directory: paths.index), monitor: LookoutMonitor(), power: LookoutPowerPolicy(),
            paths: paths, canRun: true)
    }

    /// An engine that never runs and never saves: previews, tests of other features, the test host.
    static func inert(settings: LookoutSettings = LookoutSettings()) -> LookoutEngine {
        LookoutEngine(settings: settings, repository: nil, connection: LookoutInertIndexConnection(),
                      encoder: LookoutInertQueryEncoder(), reader: LookoutInertIndexReader(),
                      monitor: LookoutInertMonitor(), power: LookoutInertPowerPolicy(),
                      paths: LookoutPaths(base: FileManager.default.temporaryDirectory
                          .appending(path: "LookoutInert", directoryHint: .isDirectory)),
                      canRun: false)
    }

    // MARK: Lifecycle

    /// Starts Lookout if it's set up and on: the power policy, the monitors, and the index service with the full
    /// root list (the service prunes everything outside it). Does nothing when it can't run or is already running.
    func start() {
        guard canRun, !isRunning, settings.isActive else { return updateStatus() }
        isRunning = true
        serviceUnavailable = false
        power.start(indexOnBattery: settings.indexOnBattery) { [weak self] in self?.powerChanged($0) }
        blocker = power.blocker
        connection.onStatus = { [weak self] in self?.received($0) }
        connection.onConnectionEvent = { [weak self] in self?.connectionChanged($0) }
        let configuration = configuration()
        monitor.start(roots: configuration.roots) { [weak self] in self?.monitorEvent($0) }
        if userPaused { connection.pause() }
        connection.start(configuration)
        search.filter = filter()
        search.isAvailable = true
        pictureSearch.filter = search.filter
        pictureSearch.isAvailable = true
        updateStatus()
    }

    /// Stops everything the engine started: tasks, monitors, the power policy, both connections, and the vectors.
    func stop() {
        syncTask?.cancel()
        syncTask = nil
        releaseTask?.cancel()
        releaseTask = nil
        warmTask?.cancel()
        warmTask = nil
        progressTask?.cancel()
        progressTask = nil
        pendingProgress = nil
        guard isRunning else { return updateStatus() }
        isRunning = false
        monitor.stop()
        power.stop()
        connection.onStatus = nil
        connection.onConnectionEvent = nil
        connection.invalidate()
        encoder.invalidate()
        search.isAvailable = false
        pictureSearch.isAvailable = false
        let reader = reader
        Task { await reader.releaseVectors() }
        indexStatus = nil
        blocker = nil
        updateStatus()
    }

    /// Saves new settings and acts on what changed: starts or stops Lookout, sends the service the new folders and
    /// exclusions (it prunes and syncs), re-watches the folders, and re-evaluates the power policy.
    func apply(_ newSettings: LookoutSettings) {
        let old = settings
        guard newSettings != old else { return }
        settings = newSettings
        do {
            try repository?.save(newSettings)
        } catch {
            LookoutLog.logger.error("Can't save Lookout settings: \(String(describing: error), privacy: .public)")
        }
        guard canRun else { return updateStatus() }
        guard newSettings.isActive else { return stop() }
        guard isRunning else { return start() }
        if newSettings.indexOnBattery != old.indexOnBattery { power.setIndexOnBattery(newSettings.indexOnBattery) }
        if newSettings.selection != old.selection || newSettings.excludedExtensions != old.excludedExtensions {
            let configuration = configuration()
            monitor.watch(roots: configuration.roots)
            connection.start(configuration)
            search.filter = filter()
            pictureSearch.filter = search.filter
            search.refresh()
            // A search with a picture under the old folders and types would keep showing their files.
            pictureSearch.refresh()
        }
        updateStatus()
    }

    /// The person paused reading. What's indexed stays searchable; new files wait too.
    func pause() {
        userPaused = true
        if isRunning { connection.pause() }
        updateStatus()
    }

    /// Undoes `pause()`, relaunching the service if it has exited.
    func resume() {
        userPaused = false
        if isRunning { connection.resume() }
        updateStatus()
    }

    // MARK: Hub

    /// The Files tab appeared: warm the query encoder and load the vectors, so the first query waits for neither.
    /// Cancels a pending vector release.
    func hubFilesDidAppear() {
        releaseTask?.cancel()
        releaseTask = nil
        guard isRunning else { return }
        startWarmUp()
        let reader = reader
        Task { await reader.prepareVectors() }
    }

    /// Warms the query encoder now, whether or not Lookout runs yet. Onboarding calls this when the model has
    /// arrived and when the first pass starts: the encoder's very first launch compiles its Metal shaders (about
    /// 5 s), and that should happen while the first pass runs, not on the first search. The encoder exits 120 s
    /// after its last call, so a later search may still pay the ordinary cold start (about 0.4 s).
    func warmQueryEncoder() {
        guard canRun else { return }
        startWarmUp()
    }

    /// Loads the query service's picture reader now: a picture is being dragged over the Hub, so it's ready by the
    /// drop. It goes away with the rest of the service 120 s after the last call. Does nothing while Lookout doesn't
    /// run.
    func warmPictureReader() {
        guard isRunning else { return }
        pictureSearch.warmUp()
    }

    private func startWarmUp() {
        guard !encoder.isWarm, warmTask == nil else { return }
        let encoder = encoder
        warmTask = Task { [weak self] in
            do {
                try await encoder.warmUp()
            } catch {
                LookoutLog.logger.info("Lookout warm-up failed: \(String(describing: error), privacy: .public)")
            }
            self?.warmTask = nil
        }
    }

    /// The Files tab hid or the Hub closed: release the vectors `vectorReleaseDelay` from now unless the tab comes back
    /// first.
    func hubDidClose() {
        releaseTask?.cancel()
        releaseTask = nil
        guard isRunning else { return }
        let reader = reader
        let delay = releaseDelay
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await reader.releaseVectors()
            self?.releaseTask = nil
        }
    }

    /// The model files finished downloading: the query encoder warms (`warmQueryEncoder`), and a running service
    /// indexes what waits, so meaning search may start.
    func modelDidArrive() {
        warmQueryEncoder()
        guard isRunning else { return }
        connection.syncNow()
        search.refresh()
    }

    // MARK: Maintenance

    /// "Read everything again" in Settings: the service reads every file once more. Names stay searchable meanwhile,
    /// and what's read becomes searchable again as it goes. Does nothing while Lookout doesn't run.
    func readEverythingAgain() {
        guard isRunning else { return }
        connection.resetIndex()
    }

    /// How long "Delete index and model" waits for the service to close the index: a batch of pictures or a step of
    /// a long PDF can take a while to commit.
    static let closeTimeout: Duration = .seconds(30)

    /// "Delete index and model" in Settings: closes the index in the service and here, stops Lookout, forgets the
    /// settings (Lookout is not set up again), and deletes the index files and the models (`LookoutDataRemoval`).
    /// The person's files are never touched.
    ///
    /// Nothing is touched until the service confirms that its store and model are closed: a batch it's committing
    /// finishes first, and deleting SQLite's files under a writer would corrupt them. Without that confirmation within
    /// `closeTimeout`, this throws, and Lookout, its settings and its files stay as they were.
    ///
    /// - Throws: `LookoutIndexCloseError` when the service didn't confirm; otherwise the first file that couldn't be
    ///   deleted (the rest are still tried).
    func deleteIndexAndModel() async throws {
        try await connection.closeIndex(timeout: Self.closeTimeout)
        apply(LookoutSettings())
        stop()
        await reader.closeIndex()
        try await LookoutDataRemoval.remove(in: paths)
    }

    /// Which of `paths` the index holds a vector for, so Find Similar can reuse it.
    func indexedPaths(_ paths: [String]) async -> Set<String> {
        guard isRunning else { return [] }
        return await reader.indexedPaths(paths)
    }

    /// For each chosen folder, how many of its files are searchable by content, for Settings.
    func searchableFileCounts() async -> [String: Int] {
        await reader.searchableFileCounts(under: settings.folders)
    }

    // MARK: Events

    private func received(_ newStatus: LookoutIndexStatus) {
        let previous = indexStatus
        indexStatus = newStatus
        serviceUnavailable = false
        if let changed = newStatus.vectorsChangedAt, changed != previous?.vectorsChangedAt {
            let reader = reader
            Task { await reader.indexDidChange() }
        }
        // The index may have just appeared: a search that found none gets another go, by words or with a picture.
        // The search with a picture is refreshed whatever its phase: one whose reader call found no index may not
        // have published `.unavailable` yet, and no later status crosses from no files to some again. The refresh's
        // generation drops that stale answer.
        if (previous?.counts.files ?? 0) == 0, newStatus.counts.files > 0 {
            if search.phase == .unavailable { search.refresh() }
            pictureSearch.refresh()
        }
        updateStatus()
    }

    private func connectionChanged(_ event: LookoutIndexConnectionEvent) {
        switch event {
        case .interrupted:
            // The process ended. If it was mid-work (a crash), its last status would claim work forever.
            if var last = indexStatus {
                switch last.activity {
                case .syncing, .indexing, .finishingLongFiles:
                    last.activity = .idle
                    (last.done, last.total, last.current) = (0, 0, nil)
                    indexStatus = last
                default:
                    break
                }
            }
        case .unavailable:
            serviceUnavailable = true
        }
        updateStatus()
    }

    private func monitorEvent(_ event: LookoutMonitorEvent) {
        switch event {
        case .foldersChanged:
            syncTask?.cancel()
            let delay = syncDebounce
            syncTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                syncTask = nil
                connection.syncNow()
            }
        case .volumesChanged:
            monitor.watch(roots: configuration().roots)
            connection.syncNow()
        case .didWake:
            connection.syncNow()
        }
    }

    private func powerChanged(_ newBlocker: LookoutBackfillBlocker?) {
        blocker = newBlocker
        connection.setBackfillAllowed(newBlocker == nil)
        // A service that exited while the backfill had to wait is woken for it.
        let counts = indexStatus?.counts
        if newBlocker == nil, !connection.isServiceRunning, counts.map({ $0.pending + $0.unfinished > 0 }) ?? true {
            connection.syncNow()
        }
        updateStatus()
    }

    // MARK: Derived

    private func updateStatus() {
        let new = LookoutStatus.map(settings: settings, index: isRunning ? indexStatus : nil, blocker: blocker,
                                    userPaused: userPaused, serviceUnavailable: serviceUnavailable)
        if new != status { status = new }
        updateProgress()
    }

    /// Feeds the tracker every status, so the pace sees every step, and publishes the result: at once when the phase
    /// changes (or progress appears or goes), else at most every `progressInterval`, with a trailing publish so the
    /// latest always shows. The trailing publish is `progressTask`, replaced by nothing and cancelled in `stop()`.
    private func updateProgress() {
        let next = progressTracker.progress(status: status, index: isRunning ? indexStatus : nil, now: now())
        guard next != (pendingProgress ?? progress) else { return }
        let elapsed = progressPublishedAt.map { ContinuousClock.now - $0 }
        if next?.phase != progress?.phase || elapsed.map({ $0 >= progressInterval }) ?? true {
            publishProgress(next)
            return
        }
        pendingProgress = .some(next)
        guard progressTask == nil, let elapsed else { return }
        let wait = progressInterval - elapsed
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, let pending = pendingProgress else { return }
            progressTask = nil
            publishProgress(pending)
        }
    }

    private func publishProgress(_ new: LookoutProgressDisplay?) {
        progressTask?.cancel()
        progressTask = nil
        pendingProgress = nil
        progressPublishedAt = ContinuousClock.now
        if new != progress { progress = new }
    }

    /// What the index service gets: the chosen folders without nested duplicates, the skips that matter, where the
    /// models and the index are, and the power policy's verdict.
    private func configuration() -> LookoutIndexConfiguration {
        let selection = settings.selection
        return LookoutIndexConfiguration(roots: selection.folders, excludedFolders: selection.effectiveSkips,
                                         excludedExtensions: settings.excludedExtensions,
                                         modelsFolder: paths.models.path, indexFolder: paths.index.path,
                                         backfillAllowed: blocker == nil)
    }

    /// The search filter for the settings, with the folders as real paths (as the index stores them). A saved folder
    /// Lookout never reads (`Rules.checkRoots`, say one that has become a link to ~/Library) shows nothing, as the
    /// index service doesn't read it either.
    private func filter() -> LookoutSearchFilter {
        let selection = settings.selection
        let real = { (path: String) in FolderSelection.realPath((path as NSString).standardizingPath) }
        return LookoutSearchFilter(folders: Rules.checkRoots(selection.folders).allowed,
                                   skipped: selection.effectiveSkips.map(real),
                                   excludedExtensions: IndexOptions.extensions(
                                       settings.excludedExtensions.joined(separator: ",")))
    }

    isolated deinit {
        syncTask?.cancel()
        releaseTask?.cancel()
        warmTask?.cancel()
        progressTask?.cancel()
    }
}
