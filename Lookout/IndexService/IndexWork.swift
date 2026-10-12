// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// The index service's work: sync, index what the sync just queued (if it's a few files: new files go first, on any
/// power source), then the backfill if allowed, then the rest of long files (`Indexer.finishLongFiles`) under the
/// same rule. Between batches it yields to a new sync, a new configuration, a pause and the backfill being turned
/// off. When it has nothing it may do, it waits a minute with the model warm (screenshots come in bursts), then the
/// process exits (`IdleExit`).
///
/// Before the model has downloaded it only syncs (file names are searchable at once) and says it's waiting; the app
/// calls `syncNow` once the download is done. Folders that aren't there (an unplugged drive) or can't be read are
/// skipped, and what was indexed from them stays. That's checked before every sync, not once: a drive ejected while
/// this runs must not crawl as "all deleted".
///
/// Threads: requests arrive on NSXPC's queues and only set flags under `lock`. All work, and every use of the store
/// and the indexer, runs on `queue`, one serial utility-QoS queue (the indexer's extraction runs one batch ahead on a
/// second thread of its own).
final class IndexWork: @unchecked Sendable {
    /// A sync that queues more files than this is a first pass or a big change: those wait for the backfill.
    static let newFilesLimit = 50
    /// Seconds with nothing to do before the process exits.
    static let idleSeconds = 60
    /// The counts (a GROUP BY over every file) are refreshed at most this often while files go by.
    static let countsInterval = 1.0

    private let queue = DispatchQueue(label: "Lookout.Index.work", qos: .utility)
    private let status: StatusBroadcaster
    private lazy var idleExit = IdleExit(after: Self.idleSeconds, on: queue) { [self] in
        indexer?.finish()
    }

    // Requests, guarded by `lock`.
    private let lock = NSLock()
    /// The configuration, sync, reset, pause and whether an app is connected (with none, work stops as DigUp's helper
    /// did when the app went away). Each waits until a pass performs it (`IndexRequests.take`).
    private var requests = IndexRequests()
    private var backfillAllowed = false
    /// Replies waiting for the index to close (`closeIndex`); the next pass closes it and calls them.
    private var closeReplies: [@Sendable () -> Void] = []
    /// Bumped by every request, so the loop notices one that came in while it decided to stop.
    private var generation = 0
    private var looping = false

    // The work queue's own state.
    private var configuration: LookoutIndexConfiguration?
    private var store: IndexStore?
    private var indexer: Indexer?
    private var roots: [URL] = []
    /// Files the last syncs queued, indexed first whatever the power policy says.
    private var newFiles = Set<Int64>()
    private var countsRefreshed = Date.distantPast

    init(status: StatusBroadcaster) {
        self.status = status
    }

    // MARK: Requests (any thread)

    /// The service launched: clear up after processes that died, and exit if nothing ever asks for work.
    func launched() {
        queue.async { ScratchFolder.removeStale() }
        idleExit.arm()
    }

    func configure(_ configuration: LookoutIndexConfiguration) {
        request {
            requests.configuration = configuration
            backfillAllowed = configuration.backfillAllowed
        }
        status.update { $0.backfillAllowed = configuration.backfillAllowed }
    }

    func syncNow() { request { requests.sync = true } }

    func setBackfillAllowed(_ allowed: Bool) {
        request { backfillAllowed = allowed }
        status.update { $0.backfillAllowed = allowed }
    }

    func pause() { request { requests.paused = true } }
    /// Goes on reading, after a crawl (`IndexRequests.resume`).
    func resume() { request { requests.resume() } }

    /// Queues every file again and syncs (`IndexStore.resetAll`).
    func resetIndex() { request { (requests.reset, requests.sync) = (true, true) } }

    /// Closes the index and forgets the configuration; `reply` runs once it's closed. A configuration that arrived
    /// before this is dropped (the app is stopping); one that arrives after it opens the index again.
    func closeIndex(reply: @escaping @Sendable () -> Void) {
        request {
            closeReplies.append(reply)
            requests.dropWork()
        }
    }

    /// Whether an app is connected. With none, work stops after the current batch.
    func setAppConnected(_ connected: Bool) { request { requests.appAway = !connected } }

    private func request(_ change: () -> Void) {
        idleExit.disarm()
        let start = lock.withLock { () -> Bool in
            change()
            generation += 1
            guard !looping else { return false }
            looping = true
            return true
        }
        if start { queue.async { [self] in loop() } }
    }

    // MARK: Loop (the work queue)

    /// Runs passes until one ends with no request having arrived during it, then arms the idle exit.
    private func loop() {
        while true {
            let seen = lock.withLock { generation }
            pass()
            let done = lock.withLock { () -> Bool in
                guard generation == seen else { return false }
                looping = false
                return true
            }
            if done { break }
        }
        idleExit.arm()
    }

    /// Requests that make a run stop between batches. The backfill also stops when it's no longer allowed.
    private func shouldYield(backfill: Bool) -> Bool {
        lock.withLock {
            requests.sync || requests.paused || requests.appAway || requests.configuration != nil
                || !closeReplies.isEmpty || (backfill && !backfillAllowed)
        }
    }

    private func pass() {
        let replies = lock.withLock {
            defer { closeReplies = [] }
            return closeReplies
        }
        if !replies.isEmpty { close(replying: replies) }
        // A held pass (paused, or no app) leaves its sync and reset waiting (`IndexRequests.take`).
        let taken = lock.withLock { requests.take() }
        let newConfiguration = taken.configuration
        if let newConfiguration {
            guard apply(newConfiguration) else { return }
        }
        guard let store, let indexer, let configuration else { return }
        if taken.isHeld {
            indexer.closeWorker()
            settle(taken.paused ? .paused : .idle, store)
            return
        }
        if taken.reset {
            do {
                try store.resetAll()
                newFiles = []
                status.update { $0.vectorsChangedAt = Date() }
            } catch {
                settle(.failed(message: "can't reset the index: \(error)"), store)
                return
            }
        }
        if taken.sync || newConfiguration != nil {
            guard self.sync(indexer, store) else { return }
        }
        if shouldYield(backfill: false) { return }
        guard LlamaModels.complete(in: URL(fileURLWithPath: configuration.modelsFolder, isDirectory: true)) else {
            // Nothing to embed with yet; the app asks for a sync once the download is done.
            settle(.waitingForModel, store)
            return
        }
        do {
            if !newFiles.isEmpty {
                try run(indexer, store, only: newFiles)
                let yielded = shouldYield(backfill: false)
                // New files a run stopped before stay first in line; done, anything still pending joins the backfill.
                newFiles = yielded ? Set(try store.pending(limit: nil, only: newFiles).map(\.id)) : []
                if yielded { return }
            }
            let backfill = lock.withLock { backfillAllowed }
            if backfill, try store.pendingCount() > 0 {
                try run(indexer, store, only: nil)
                if shouldYield(backfill: true) { return }
            }
            // Once nothing is waiting: the rest of long PDFs and documents, the same way.
            if backfill, try store.pendingCount() == 0, try store.unfinishedCount().files > 0 {
                try finishLongFiles(indexer, store)
                if shouldYield(backfill: true) { return }
            }
            settle(.idle, store)
        } catch {
            // The model can't run, or the index can't be written: stop until the next request, never retry here.
            indexer.closeWorker()
            settle(.failed(message: "\(error)"), store)
        }
    }

    /// Frees the model and closes the store (its last reference goes, so SQLite closes the file), then answers. The
    /// app deletes the index once it hears back, so the answer comes only once the store is really gone: if anything
    /// still holds it, there's no answer, the app's wait times out, and nothing is deleted.
    private func close(replying replies: [@Sendable () -> Void]) {
        indexer?.finish()
        weak let closing = store
        (store, indexer, configuration) = (nil, nil, nil)
        guard closing == nil else {
            settle(.failed(message: "the index is still open after closing it; the close isn't confirmed"), nil)
            return
        }
        roots = []
        newFiles = []
        status.update {
            $0.activity = .idle
            ($0.done, $0.total, $0.current) = (0, 0, nil)
            $0.counts = IndexStore.Counts()
        }
        replies.forEach { $0() }
    }

    /// Opens the store and makes the indexer for a configuration, checks the model and drops files under none of the
    /// roots. False when the index can't be opened (the status says why).
    private func apply(_ new: LookoutIndexConfiguration) -> Bool {
        do {
            let folder = URL(fileURLWithPath: new.indexFolder, isDirectory: true)
            if store?.directory.standardizedFileURL != folder.standardizedFileURL {
                indexer?.finish()
                (store, indexer) = (nil, nil)
                store = try IndexStore(directory: folder)
            }
            guard let store else { return false }
            if indexer == nil || configuration?.options != new.options || configuration?.modelsFolder != new.modelsFolder {
                indexer?.finish()
                let made = try Indexer(store: store, options: new.options) {
                    try LlamaEmbedder(models: LlamaModels.locate(in: URL(fileURLWithPath: new.modelsFolder)),
                                      textOnly: false, log: try? LookoutPaths.standard.logFile("index-service.log"))
                }
                // A new version may bring a new model: the index starts over by itself (keyword search on names
                // goes on meanwhile).
                made.embedderSource = LlamaEmbedder.modelInfo.vectorSource
                made.resetOnModelChange = { [status] _, _ in status.update { $0.vectorsChangedAt = Date() } }
                indexer = made
            }
            configuration = new
            roots = new.allowedRoots
            newFiles = []
            try indexer?.checkModel()
            // Folders taken out of the app leave the index; folders that are only missing right now keep their files.
            if try store.prune(keepingUnder: roots.map(\.path)) > 0 {
                status.update { $0.vectorsChangedAt = Date() }
            }
            return true
        } catch {
            configuration = nil
            settle(.failed(message: "can't open the index: \(error)"), store)
            return false
        }
    }

    /// Crawls the roots that are there and readable, and reconciles the index. False when the sync failed (the
    /// status says why).
    private func sync(_ indexer: Indexer, _ store: IndexStore) -> Bool {
        status.update {
            $0.activity = .syncing
            ($0.done, $0.total, $0.current) = (0, 0, nil)
        }
        let availability = RootAvailability.check(roots)
        store.scope = availability.available.map(\.path)
        status.update {
            $0.missingRoots = availability.missing
            $0.notPermittedRoots = availability.notPermitted
        }
        do {
            let summary = try indexer.sync(availability.available)
            if summary.queued.count <= Self.newFilesLimit { newFiles.formUnion(summary.queued) }
            if summary.vectorsChanged { status.update { $0.vectorsChangedAt = Date() } }
            refreshCounts(store, force: true)
            return true
        } catch {
            settle(.failed(message: "sync failed: \(error)"), store)
            return false
        }
    }

    /// A close is waiting: a batch already read is dropped rather than committed, so the reply comes sooner.
    private func closeRequested() -> Bool {
        lock.withLock { !closeReplies.isEmpty }
    }

    private func run(_ indexer: Indexer, _ store: IndexStore, only ids: Set<Int64>?) throws {
        let isNew = ids != nil
        status.update { $0.activity = .indexing }
        try indexer.run(only: ids, shouldStop: { [self] in shouldYield(backfill: !isNew) },
                        shouldAbandon: { [self] in closeRequested() }, onEvent: { [self] event in
            report(event.path, event.kind, event.state, done: event.done, total: event.total, store)
        })
    }

    private func finishLongFiles(_ indexer: Indexer, _ store: IndexStore) throws {
        status.update { $0.activity = .finishingLongFiles }
        try indexer.finishLongFiles(shouldStop: { [self] in shouldYield(backfill: true) },
                                    shouldAbandon: { [self] in closeRequested() }, onStep: { [self] step in
            report(step.path, step.kind, step.state, done: step.done, total: step.total, store)
        })
    }

    /// One file read: progress, the file for the onboarding feed, and a reload hint when its segments changed. A
    /// file comes back `pending` only when the indexer queued it again because another file is at its path
    /// (`QueuedFileGate`), which deletes its segments.
    private func report(_ path: String, _ kind: FileKind, _ state: String, done: Int, total: Int, _ store: IndexStore) {
        let segmentsChanged = state == "done" || state == "partial" || state == "pending"
        status.update {
            ($0.done, $0.total) = (done, total)
            $0.current = .init(kind: kind, name: (path as NSString).lastPathComponent)
            if segmentsChanged { $0.vectorsChangedAt = Date() }
        }
        refreshCounts(store, force: false)
    }

    /// Ends a pass: the activity it ended in, fresh counts, no progress.
    private func settle(_ activity: LookoutIndexStatus.Activity, _ store: IndexStore?) {
        if let store { refreshCounts(store, force: true) }
        status.update {
            $0.activity = activity
            ($0.done, $0.total, $0.current) = (0, 0, nil)
        }
    }

    private func refreshCounts(_ store: IndexStore, force: Bool) {
        guard force || Date().timeIntervalSince(countsRefreshed) >= Self.countsInterval,
              let counts = try? store.counts() else { return }
        countsRefreshed = Date()
        status.update { $0.counts = counts }
    }
}
