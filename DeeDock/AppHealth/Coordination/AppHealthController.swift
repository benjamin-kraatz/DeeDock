import Foundation
import Observation

/// Owns App Health's lifecycle: the collection switch, suspension on sleep, display sleep and inactive sessions,
/// the 20-second sampling loop, termination signals, the in-memory history, and every write to the record store.
///
/// `DeeDockDelegate` creates it, calls `start()` after the docks start and `stop()` at quit. Collection runs only
/// while `settings.collecting` is on and no suspension reason holds. Every task, observer, and pending lookup it
/// starts is cancelled or removed when collection stops, pauses, or DOKK quits.
///
/// Labelling builds on three seams:
/// - `tickCompleted` (and the observable `lastTick`) after every written tick, with `history(for:)` for windows;
/// - `writePrompt(_:at:)`, `writeLabel(_:at:)`, `writeEvent(_:at:)`, and `backfill(app:from:to:)`;
/// - `willPause`, called before sampling stops for any reason, so an open prompt can be closed and recorded as
///   interrupted while writes are still accepted.
@MainActor @Observable
final class AppHealthController {
    /// What the collector is doing, for Settings.
    enum Phase: Equatable {
        /// Collection is off.
        case off
        /// Sampling every 20 seconds.
        case collecting
        /// Collection is on, but sleep, display sleep, or an inactive session paused sampling.
        case paused
    }

    /// Why sampling is paused while collection is on.
    enum SuspensionReason: Hashable, CaseIterable {
        case systemSleep, displaySleep, sessionInactive

        var collectorReason: AppHealthCollectorReason {
            switch self {
            case .systemSleep: .sleep
            case .displaySleep: .displaySleep
            case .sessionInactive: .session
            }
        }
    }

    /// Long-running storage work started from Settings.
    enum StorageActivity: Equatable {
        case idle, exporting, deleting
    }

    /// Storage work that failed, for Settings to explain.
    enum StorageError: Equatable {
        case exportFailed, deleteFailed
    }

    nonisolated static let tickInterval: Duration = .seconds(20)
    nonisolated static let crashReportDelay: Duration = .seconds(5)
    /// A crash report counts if it was written up to this long before the termination notification.
    nonisolated static let crashReportLeeway: TimeInterval = 10

    let settings: AppHealthSettingsStore
    let labelling: AppHealthLabellingPreferences
    private(set) var phase: Phase = .off
    /// Size, age, and day count of the stored data.
    private(set) var storage: AppHealthStorageSummary = .empty
    private(set) var storageActivity: StorageActivity = .idle
    private(set) var storageError: StorageError?
    /// The most recent written tick. Nil while collection is off or before the first tick after a resume.
    private(set) var lastTick: AppHealthTickReport?

    /// Called on the main actor after each tick's records are queued, with every watched app's sample.
    @ObservationIgnored var tickCompleted: ((AppHealthTickReport) -> Void)?
    /// Called on the main actor before sampling stops (collection off, sleep, display sleep, inactive session,
    /// quit). Writes made from it are still recorded, ahead of the `collectorStop` event.
    @ObservationIgnored var willPause: ((AppHealthCollectorReason) -> Void)?
    /// Finds where a prompt about an app attaches. Injected by the delegate from `DockCoordinator`.
    @ObservationIgnored var anchorProvider: ((String) -> AppHealthAnchor?)?

    /// Whether labelling may prompt: both switches on. Prompts also wait for a tick, so none appear while paused.
    var isLabellingActive: Bool { settings.collecting && settings.labelling }

    @ObservationIgnored private let dependencies: AppHealthControllerDependencies
    @ObservationIgnored private var started = false
    /// True while collection is on: observers are installed and writes are accepted.
    @ObservationIgnored private var recording = false
    @ObservationIgnored private var suspension: Set<SuspensionReason> = []
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    /// Bumped whenever sampling starts or stops, so a tick that was awaiting the sampler cannot write after a stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var power = AppHealthPowerSource.unknown
    @ObservationIgnored private var thermal = AppHealthThermalState.nominal
    @ObservationIgnored private var recentHistory = AppHealthHistory()
    @ObservationIgnored private var writeStates: [String: AppHealthWritePolicy.AppState] = [:]
    /// Apps whose last responsiveness check timed out, so they are checked again next tick.
    @ObservationIgnored private var failedHangChecks: Set<String> = []
    @ObservationIgnored private var pendingTerminations: [UUID: PendingTermination] = [:]
    /// The tail of the serial write queue. Each write awaits the previous one, so records reach the file in the
    /// order they were queued. Detached: it never needs the main actor.
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    @ObservationIgnored private var storageTask: Task<Void, Never>?

    /// A terminated app's event, held while its crash-report lookup runs.
    private struct PendingTermination {
        let app: String
        let terminatedAt: Date
        var event: AppHealthEventRecord
        var lookup: Task<Void, Never>?
    }

    init(settings: AppHealthSettingsStore, labelling: AppHealthLabellingPreferences,
         dependencies: AppHealthControllerDependencies) {
        self.settings = settings
        self.labelling = labelling
        self.dependencies = dependencies
    }

    /// The production controller: persisted switches and preferences, live services.
    static func live() -> AppHealthController {
        AppHealthController(settings: AppHealthSettingsStore(defaults: .standard),
                            labelling: AppHealthLabellingPreferences(defaults: .standard),
                            dependencies: .live())
    }

    isolated deinit {
        samplingTask?.cancel()
        pendingTerminations.values.forEach { $0.lookup?.cancel() }
        summaryTask?.cancel()
        storageTask?.cancel()
        dependencies.observers.stop()
    }

    // MARK: - Lifecycle

    /// Begins collecting if the switch is on. Call once after the docks start.
    func start() {
        guard !started else { return }
        started = true
        refreshSummary()
        if settings.collecting { beginRecording() }
    }

    /// Stops collecting for quit and waits briefly for the final records to reach disk.
    func stop() {
        guard started else { return }
        endRecording(.quit)
        started = false
        summaryTask?.cancel()
        flushWritesBeforeExit()
    }

    /// The collection switch. Turning it off also makes labelling inert; the labelling switch keeps its value.
    func setCollecting(_ value: Bool) {
        settings.setCollecting(value)
        guard started else { return }
        if value { beginRecording() } else { endRecording(.disabled) }
    }

    func setLabelling(_ value: Bool) {
        settings.setLabelling(value)
    }

    private func beginRecording() {
        guard !recording else { return }
        recording = true
        suspension = []
        power = dependencies.powerSource()
        thermal = dependencies.thermalState()
        dependencies.observers.start { [weak self] event in self?.handle(event) }
        startSampling(.enabled)
    }

    private func endRecording(_ reason: AppHealthCollectorReason) {
        guard recording else { return }
        pauseSampling(reason)
        dependencies.observers.stop()
        recording = false
        suspension = []
        recentHistory.removeAll()
        writeStates.removeAll()
        failedHangChecks.removeAll()
        lastTick = nil
        updatePhase()
    }

    // MARK: - System events

    private func handle(_ event: AppHealthSystemEvent) {
        guard recording else { return }
        switch event {
        case .willSleep: suspend(.systemSleep, event: .sleep)
        case .didWake: resume(.systemSleep, event: .wake)
        case .screensDidSleep: suspend(.displaySleep, event: .displaySleep)
        case .screensDidWake: resume(.displaySleep, event: .displayWake)
        case .sessionDidResignActive: suspend(.sessionInactive, event: .sessionInactive)
        case .sessionDidBecomeActive: resume(.sessionInactive, event: .sessionActive)
        case .launched(let app):
            enqueue(.event(.app(.launched, app.bundleID, kind: app.kind)))
        case .terminated(let app):
            applicationTerminated(app)
        case .thermalStateChanged:
            let state = dependencies.thermalState()
            guard state != thermal else { return }
            thermal = state
            enqueue(.event(AppHealthEventRecord(event: .thermal, thermal: state)))
        case .powerSourceChanged:
            let source = dependencies.powerSource()
            guard source != power else { return }
            power = source
            enqueue(.event(AppHealthEventRecord(event: .power, power: source)))
        }
    }

    private func suspend(_ reason: SuspensionReason, event: AppHealthEventKind) {
        suspension.insert(reason)
        enqueue(.event(AppHealthEventRecord(event: event)))
        pauseSampling(reason.collectorReason)
        updatePhase()
    }

    private func resume(_ reason: SuspensionReason, event: AppHealthEventKind) {
        suspension.remove(reason)
        enqueue(.event(AppHealthEventRecord(event: event)))
        // A display waking must not restart sampling for an inactive session or a sleeping Mac.
        if suspension.isEmpty { startSampling(reason.collectorReason) }
        updatePhase()
    }

    // MARK: - Sampling

    private func startSampling(_ reason: AppHealthCollectorReason) {
        guard recording, suspension.isEmpty, samplingTask == nil else { return }
        generation &+= 1
        let generation = generation
        enqueue(.event(.collector(.collectorStart, reason: reason)))
        let sampler = dependencies.sampler
        let waitForNextTick = dependencies.waitForNextTick
        samplingTask = Task { [weak self] in
            // Counters accumulated across a sleep or a pause would read as one huge interval, so the first pass
            // after every start only re-establishes baselines and writes nothing.
            await sampler.resetBaselines()
            var baseline = true
            // macOS posts no notification for per-process resource use, so this loop is the only way to observe
            // it. `waitForNextTick` sleeps 20 s with 2 s tolerance so the system can coalesce the wake-up.
            while !Task.isCancelled {
                if let self { await self.tick(generation: generation, baseline: baseline) } else { return }
                baseline = false
                do { try await waitForNextTick() } catch { return }
            }
        }
        updatePhase()
    }

    /// Cancels sampling, any responsiveness checks it is awaiting, and pending crash-report lookups.
    private func pauseSampling(_ reason: AppHealthCollectorReason) {
        willPause?(reason)
        flushPendingTerminations()
        guard let samplingTask else { return }
        samplingTask.cancel()
        self.samplingTask = nil
        generation &+= 1
        lastTick = nil
        enqueue(.event(.collector(.collectorStop, reason: reason)))
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && !Task.isCancelled
    }

    private func tick(generation: Int, baseline: Bool) async {
        let snapshot = dependencies.snapshot(dependencies.now(), power, thermal)
        let result = await dependencies.sampler.sample(snapshot.apps)
        guard isCurrent(generation), !baseline, let interval = result.interval, interval > 0 else { return }

        var kinds: [String: AppHealthAppKind] = [:]
        var mainProcesses: [String: pid_t] = [:]
        for app in snapshot.apps where kinds[app.bundleID] == nil {
            kinds[app.bundleID] = app.kind
            mainProcesses[app.bundleID] = app.pid
        }
        var samples: [String: AppHealthSample] = [:]
        for (app, usage) in result.usage {
            guard let kind = kinds[app] else { continue }
            samples[app] = AppHealthSample(
                app: app, kind: kind, timestamp: snapshot.date, interval: interval, cpuMain: usage.cpuMain,
                cpuHelpers: usage.cpuHelpers, mem: usage.mem, memMain: usage.memMain, procs: usage.procs,
                wakeups: usage.wakeups, energy: usage.energy, frontmost: app == snapshot.frontmost)
        }

        if snapshot.accessibilityTrusted {
            let candidates = AppHealthHangCandidates.select(
                samples.values.map { .init(app: $0.app, kind: $0.kind, cpuPercent: $0.cpuPercent, frontmost: $0.frontmost) },
                failedLastCheck: failedHangChecks)
            for app in candidates {
                guard isCurrent(generation) else { return }
                guard let pid = mainProcesses[app] else { continue }
                let check = await dependencies.hangChecker.check(pid: pid)
                guard isCurrent(generation) else { return }
                samples[app]?.hang = check.result
                samples[app]?.hangMs = check.milliseconds
                if check.result == .timeout { failedHangChecks.insert(app) } else { failedHangChecks.remove(app) }
            }
        }

        var records: [AppHealthRecord] = []
        for sample in samples.values.sorted(by: { $0.app < $1.app }) {
            var state = writeStates[sample.app] ?? AppHealthWritePolicy.AppState()
            let reason = AppHealthWritePolicy.decide(sample, state: &state)
            writeStates[sample.app] = state
            recentHistory.append(sample, written: reason != nil)
            if let reason { records.append(AppHealthRecord(.sample(AppHealthSampleRecord(sample, why: reason)), at: snapshot.date)) }
        }
        let tickRecord = AppHealthTickRecord(interval: interval, frontmost: snapshot.frontmost, idle: snapshot.idleSeconds,
                                             power: snapshot.power, thermal: snapshot.thermal, apps: kinds.count,
                                             written: records.count, costMs: result.costMilliseconds,
                                             ax: snapshot.accessibilityTrusted)
        enqueue([AppHealthRecord(.tick(tickRecord), at: snapshot.date)] + records)

        let report = AppHealthTickReport(date: snapshot.date, interval: interval, frontmost: snapshot.frontmost,
                                         idleSeconds: snapshot.idleSeconds, power: snapshot.power,
                                         thermal: snapshot.thermal, accessibilityTrusted: snapshot.accessibilityTrusted,
                                         samples: samples)
        lastTick = report
        tickCompleted?(report)
    }

    // MARK: - Terminations

    /// Captures the termination signals now, from history, then writes the event once the crash-report lookup
    /// finishes, timestamped at the termination.
    private func applicationTerminated(_ app: AppHealthAppIdentity) {
        let terminatedAt = dependencies.now()
        let signals = AppHealthTerminationSignals.evaluate(recentHistory.entries(for: app.bundleID).map(\.sample),
                                                           terminatedAt: terminatedAt)
        let event = AppHealthEventRecord(
            event: .terminated, app: app.bundleID, kind: app.kind,
            runSeconds: app.launchDate.map { max(0, Int(terminatedAt.timeIntervalSince($0))) },
            heavyBefore: signals.heavyBefore, hangFailing: signals.hangFailing,
            frontmostRecently: signals.frontmostRecently)
        let id = UUID()
        pendingTerminations[id] = PendingTermination(app: app.bundleID, terminatedAt: terminatedAt, event: event)
        guard let executable = app.executableName else {
            finishTermination(id, crashReport: nil)
            return
        }
        let delay = dependencies.crashReportDelay
        let crashReports = dependencies.crashReports
        let since = terminatedAt.addingTimeInterval(-Self.crashReportLeeway)
        pendingTerminations[id]?.lookup = Task { [weak self] in
            do { try await delay() } catch { return }
            let found = await crashReports.hasReport(executableName: executable, since: since)
            guard !Task.isCancelled else { return }
            self?.finishTermination(id, crashReport: found)
        }
    }

    /// Writes a held termination event and drops the app's history up to the termination. Idempotent.
    private func finishTermination(_ id: UUID, crashReport: Bool?) {
        guard var pending = pendingTerminations.removeValue(forKey: id) else { return }
        pending.event.crashReport = crashReport
        enqueue([AppHealthRecord(.event(pending.event), at: pending.terminatedAt)])
        recentHistory.removeEntries(for: pending.app, through: pending.terminatedAt)
        if recentHistory.entries(for: pending.app).isEmpty {
            writeStates[pending.app] = nil
            failedHangChecks.remove(pending.app)
        }
    }

    /// Cancels every pending lookup and writes its event without `crashReport`, so no termination is lost.
    private func flushPendingTerminations() {
        for (id, pending) in pendingTerminations {
            pending.lookup?.cancel()
            finishTermination(id, crashReport: nil)
        }
    }

    // MARK: - Labelling seams

    /// An app's last ten minutes of computed samples, oldest first, with whether each is on disk.
    func history(for app: String) -> [AppHealthHistoryEntry] {
        recentHistory.entries(for: app)
    }

    /// Apps with in-memory history.
    var historyApps: [String] { recentHistory.apps }

    /// Where a prompt about `bundleID` attaches right now; nil without an injected provider.
    func anchor(forBundleID bundleID: String) -> AppHealthAnchor? {
        anchorProvider?(bundleID)
    }

    /// Writes an `event` record. Ignored while collection is off.
    func writeEvent(_ event: AppHealthEventRecord, at date: Date? = nil) {
        guard recording else { return }
        enqueue([AppHealthRecord(.event(event), at: date ?? dependencies.now())])
    }

    /// Writes a `prompt` record. Ignored while collection is off. Call `backfill(app:from:to:)` for its window.
    func writePrompt(_ prompt: AppHealthPromptRecord, at date: Date? = nil) {
        guard recording else { return }
        enqueue([AppHealthRecord(.prompt(prompt), at: date ?? dependencies.now())])
    }

    /// Writes a `label` record. Ignored while collection is off; `willPause` runs while it is still on.
    func writeLabel(_ label: AppHealthLabelRecord, at date: Date? = nil) {
        guard recording else { return }
        enqueue([AppHealthRecord(.label(label), at: date ?? dependencies.now())])
    }

    /// Writes every in-memory tick of `app` inside `from…to` that is not on disk yet, as `backfill` rows, so a
    /// labelled window is complete. Each tick is written at most once.
    ///
    /// - Returns: How many rows were written.
    @discardableResult
    func backfill(app: String, from: Date, to: Date) -> Int {
        guard recording else { return 0 }
        let samples = recentHistory.takeUnwritten(app: app, from: from, to: to)
        guard !samples.isEmpty else { return 0 }
        var state = writeStates[app] ?? AppHealthWritePolicy.AppState()
        for sample in samples { AppHealthWritePolicy.noteWritten(sample, state: &state) }
        writeStates[app] = state
        enqueue(samples.map { AppHealthRecord(.sample(AppHealthSampleRecord($0, why: .backfill)), at: $0.timestamp) })
        return samples.count
    }

    /// "Don't ask about this app": adds it to the list and writes `dontAsk`.
    func dontAsk(about app: String) {
        guard labelling.addDontAsk(app) else { return }
        writeEvent(.app(.dontAsk, app))
    }

    /// Removes an app from the "Don't ask" list and writes `allowAsk`.
    func allowAsking(about app: String) {
        guard labelling.removeDontAsk(app) else { return }
        writeEvent(.app(.allowAsk, app))
    }

    /// "Pause labelling for today": silent until the next local midnight. Writes `pauseToday`.
    func pauseLabellingForToday() {
        labelling.pauseForToday()
        writeEvent(AppHealthEventRecord(event: .pauseToday))
    }

    /// Ends a pause early and writes `resume`.
    func resumeLabelling() {
        guard labelling.resume() else { return }
        writeEvent(AppHealthEventRecord(event: .resume))
    }

    // MARK: - Storage

    /// Re-reads the storage summary once queued writes have landed.
    func refreshSummary() {
        let chain = writeChain
        let store = dependencies.store
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            await chain?.value
            let summary = await store.summary()
            guard !Task.isCancelled else { return }
            self?.storage = summary
        }
    }

    /// Writes a zip of every file plus a manifest to `destination`, after queued writes land.
    func export(to destination: URL) {
        guard storageActivity == .idle else { return }
        storageActivity = .exporting
        storageError = nil
        let manifest = AppHealthExportManifest(exportedAt: dependencies.now(), dokkVersion: dependencies.appVersion(),
                                               sampleInterval: Int(Self.tickInterval.components.seconds))
        let chain = writeChain
        let store = dependencies.store
        storageTask = Task { [weak self] in
            await chain?.value
            let succeeded: Bool
            do {
                try await store.export(to: destination, manifest: manifest)
                succeeded = true
            } catch {
                succeeded = false
            }
            guard let self else { return }
            storageActivity = .idle
            if succeeded { Analytics.count(.appHealthExported) } else { storageError = .exportFailed }
        }
    }

    /// Removes every App Health file. Queued writes land first; later writes start a new file.
    func deleteAllData() {
        guard storageActivity == .idle else { return }
        storageActivity = .deleting
        storageError = nil
        // Quiet apps get a fresh baseline row in the new file instead of waiting up to 30 minutes.
        writeStates.removeAll()
        let previous = writeChain
        let store = dependencies.store
        let deletion = Task.detached { () -> Bool in
            await previous?.value
            do { try await store.deleteAll(); return true } catch { return false }
        }
        writeChain = Task.detached { _ = await deletion.value }
        storageTask = Task { [weak self] in
            let succeeded = await deletion.value
            guard let self else { return }
            storageActivity = .idle
            if !succeeded { storageError = .deleteFailed }
            refreshSummary()
        }
    }

    func clearStorageError() {
        storageError = nil
    }

    // MARK: - Writing

    private func enqueue(_ body: AppHealthRecord.Body) {
        enqueue([AppHealthRecord(body, at: dependencies.now())])
    }

    private func enqueue(_ records: [AppHealthRecord]) {
        guard !records.isEmpty else { return }
        let previous = writeChain
        let store = dependencies.store
        writeChain = Task.detached(priority: .utility) {
            await previous?.value
            await store.append(records)
        }
        refreshSummary()
    }

    /// `applicationWillTerminate` returns and the process exits right after, so the final records (interrupted
    /// labels, `collectorStop`) would be lost in the queue. Block for at most a second until they are written and the
    /// file is closed. Nothing awaited here needs the main actor, so the wait cannot deadlock.
    private func flushWritesBeforeExit() {
        let chain = writeChain
        let store = dependencies.store
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await chain?.value
            await store.close()
            done.signal()
        }
        _ = done.wait(timeout: .now() + .seconds(1))
    }

    private func updatePhase() {
        let next: Phase = !recording ? .off : samplingTask != nil ? .collecting : .paused
        if next != phase { phase = next }
    }
}
