import Foundation
import Observation

/// Copy and move queue for the Files tab.
///
/// Jobs run one at a time in FIFO order on a private serial dispatch queue (a paused copy blocks
/// its thread, which must not be one of Swift concurrency's few cooperative threads). Progress
/// arrives on the main actor about 30 times a second. The queue outlives the Hub panel, so a copy
/// keeps going after the Hub closes and the DOKK tile's ring can show it.
@MainActor @Observable
final class HubFileTransferQueue {
    nonisolated enum Kind: Sendable, Hashable { case copy, move }

    /// A job's state. Waiting jobs are `.running` (or `.paused` when paused before they started);
    /// only `jobs.first` is actually transferring. `failed` carries a localized message.
    nonisolated enum State: Sendable, Hashable { case running, paused, finished, cancelled, failed(String) }

    /// One copy or move of one or more items into one folder.
    nonisolated struct Job: Identifiable, Sendable, Hashable {
        let id: UUID
        let kind: Kind
        let sources: [URL]
        let destination: URL
        var completedBytes: Int64
        /// Zero until the worker has sized the job, and for same-volume moves (instant renames).
        var totalBytes: Int64
        var state: State
        /// 0…1. A finished job reports 1 even when it had no bytes to copy.
        var fractionCompleted: Double {
            if state == .finished { return 1 }
            return totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
        }
        /// Display name of the first source's folder.
        var sourceFolderName: String
        /// Display name of the destination folder.
        var destinationFolderName: String
    }

    /// Pending and running jobs, oldest first. `jobs.first` is the one transferring.
    private(set) var jobs: [Job] = []
    /// The most recently ended job with its final state (finished, cancelled, or failed). Cleared
    /// 2.2 s after it was set; the UI shows "Copied 3 items" or the failure from it.
    private(set) var lastFinished: Job?

    /// Byte progress over all queued jobs, or nil when idle. Drives the DOKK tile's ring.
    var overallProgress: Double? {
        guard !jobs.isEmpty else { return nil }
        let total = jobs.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard total > 0 else { return 0 }
        return min(1, Double(jobs.reduce(Int64(0)) { $0 + $1.completedBytes }) / Double(total))
    }

    @ObservationIgnored private let workerQueue = DispatchQueue(label: "DeeDock.HubFileTransfer", qos: .userInitiated)
    @ObservationIgnored private let callbackHook: (@Sendable (HubFileTransferControl) -> Void)?
    /// The running job's switches; nil while idle.
    @ObservationIgnored private var activeControl: (id: UUID, control: HubFileTransferControl)?
    /// Owns the running job until it ends. Cancelling it does not stop the copy; `cancel(_:)` does.
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var clearFinished: Task<Void, Never>?
    /// Cross-volume flags reported by the worker, kept for the job's analytics event.
    @ObservationIgnored private var crossVolume: [UUID: Bool] = [:]
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter callbackHook: Test hook run on the worker thread from every copy status
    ///   callback, used to pause or cancel deterministically mid-copy.
    nonisolated init(callbackHook: (@Sendable (HubFileTransferControl) -> Void)? = nil) {
        self.callbackHook = callbackHook
    }

    /// Adds a job and starts it when nothing else is running.
    ///
    /// For a move, sources already inside `destination` are skipped (dropping onto their own
    /// folder is a no-op). A copy into the item's own folder duplicates it as "Name copy".
    /// - Returns: The new job's ID; the job may finish (or be dropped as empty) before the caller
    ///   looks it up.
    @discardableResult
    func enqueue(_ kind: Kind, sources: [URL], to destination: URL) -> Job.ID {
        let destination = destination.standardizedFileURL
        var sources = sources.map(\.standardizedFileURL)
        if kind == .move {
            sources.removeAll { Self.samePath($0.deletingLastPathComponent(), destination) }
        }
        let id = UUID()
        guard !sources.isEmpty else { return id }
        let fileManager = FileManager.default
        jobs.append(Job(
            id: id, kind: kind, sources: sources, destination: destination,
            completedBytes: 0, totalBytes: 0, state: .running,
            sourceFolderName: fileManager.displayName(atPath: sources[0].deletingLastPathComponent().path),
            destinationFolderName: fileManager.displayName(atPath: destination.path)))
        startNextIfNeeded()
        return id
    }

    /// Pauses a job mid-file, or holds a waiting job when it reaches the front.
    func pause(_ id: Job.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        jobs[index].state = .paused
        if activeControl?.id == id { activeControl?.control.pause() }
    }

    func resume(_ id: Job.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .paused else { return }
        jobs[index].state = .running
        if activeControl?.id == id { activeControl?.control.resume() }
    }

    /// Cancels a job. A running copy stops at its next status callback and removes the partial
    /// item; a waiting job is dropped at once.
    func cancel(_ id: Job.ID) {
        if activeControl?.id == id {
            activeControl?.control.cancel()
            return
        }
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var job = jobs.remove(at: index)
        job.state = .cancelled
        ended(job)
    }

    /// Cancels every job. Waiting jobs are dropped at once; the running one stops at its next
    /// status callback and removes its partial item on the worker queue, after this returns.
    func cancelAll() {
        for job in jobs.reversed() { cancel(job.id) }
    }

    /// Cancels every job and blocks until the worker has stopped and removed the partial
    /// destination item, or until `timeout` passes. For app termination only, where the process
    /// would otherwise exit before the asynchronous cleanup in ``cancelAll()`` runs.
    ///
    /// Waiting on the serial worker queue is safe from the main thread: the worker never waits for
    /// the main actor (progress goes through an unbounded stream), and the next job cannot start
    /// because starting one needs the main actor. A copyfile call stuck on an unresponsive volume
    /// does not reach its next callback, so the timeout bounds termination; such a partial item
    /// stays behind.
    func cancelAllForTermination(timeout: DispatchTimeInterval = .seconds(3)) {
        let wasRunning = activeControl != nil
        cancelAll()
        guard wasRunning else { return }
        let drained = DispatchSemaphore(value: 0)
        workerQueue.async { drained.signal() }
        _ = drained.wait(timeout: .now() + timeout)
    }

    /// Resumes once no job is queued. For tests and termination handling.
    func waitUntilIdle() async {
        guard !jobs.isEmpty else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: - Running

    private func startNextIfNeeded() {
        guard runner == nil, let job = jobs.first else { return }
        let control = HubFileTransferControl(paused: job.state == .paused)
        activeControl = (job.id, control)
        let worker = HubFileTransferWorker(kind: job.kind, sources: job.sources, destination: job.destination,
                                           control: control, callbackHook: callbackHook)
        let queue = workerQueue
        runner = Task { [weak self] in
            let (events, sink) = AsyncStream.makeStream(of: HubFileTransferWorker.Event.self,
                                                        bufferingPolicy: .unbounded)
            let consumer = Task { [weak self] in
                for await event in events { self?.apply(event, to: job.id) }
            }
            let outcome = await withCheckedContinuation { continuation in
                queue.async {
                    let outcome = worker.run { sink.yield($0) }
                    sink.finish()
                    continuation.resume(returning: outcome)
                }
            }
            await consumer.value
            self?.finish(job.id, outcome: outcome)
        }
    }

    private func apply(_ event: HubFileTransferWorker.Event, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .total(let bytes): jobs[index].totalBytes = bytes
        case .progress(let bytes): jobs[index].completedBytes = bytes
        case .crossVolume(let value): crossVolume[id] = value
        }
    }

    private func finish(_ id: UUID, outcome: HubFileTransferWorker.Outcome) {
        runner = nil
        activeControl = nil
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            var job = jobs.remove(at: index)
            switch outcome {
            case .completed:
                job.state = .finished
                job.completedBytes = job.totalBytes
            case .cancelled: job.state = .cancelled
            case .failed(let message): job.state = .failed(message)
            }
            ended(job)
        }
        startNextIfNeeded()
    }

    /// Publishes a job's end, records analytics, and wakes idle waiters.
    private func ended(_ job: Job) {
        lastFinished = job
        clearFinished?.cancel()
        clearFinished = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.lastFinished = nil
        }
        let outcome: AnalyticsHubTransferOutcome = switch job.state {
        case .finished: .completed
        case .failed: .failed
        default: .cancelled
        }
        // A job cancelled before it started never reported; reading volumes here is not worth it.
        let crossVolume = self.crossVolume.removeValue(forKey: job.id) ?? false
        Analytics.track(.hubFileTransfer(job.kind == .copy ? .copy : .move, itemCount: job.sources.count,
                                         crossVolume: crossVolume, outcome: outcome))
        if jobs.isEmpty {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    // MARK: - Drop rules

    /// Finder's rule: Option forces a copy; otherwise items on the destination's volume move and
    /// items from another volume copy. An unknown volume copies, the safe choice. Reads resource
    /// values (cheap, cached by the system) and can be called during drag tracking.
    nonisolated static func defaultKind(sources: [URL], destination: URL, optionHeld: Bool) -> Kind {
        if optionHeld { return .copy }
        return isCrossVolume(sources: sources, destination: destination) ? .copy : .move
    }

    /// Whether any source lives on a different (or unknown) volume than `destination`.
    nonisolated static func isCrossVolume(sources: [URL], destination: URL) -> Bool {
        guard let target = HubDirectoryLister.volumeIdentifier(of: destination) else { return true }
        return sources.contains { HubDirectoryLister.volumeIdentifier(of: $0) != target }
    }

    /// Whether dropping `sources` on `destination` makes sense.
    ///
    /// False for an empty drop, a folder dropped onto itself or one of its descendants, and a
    /// drop where every item already sits directly in `destination`. Paths are compared after
    /// resolving symbolic links (`/tmp` and `/private/tmp` are the same folder).
    nonisolated static func isValidDrop(sources: [URL], destination: URL) -> Bool {
        guard !sources.isEmpty else { return false }
        let target = canonicalPath(destination)
        for source in sources {
            let path = canonicalPath(source)
            if target == path || target.hasPrefix(path.hasSuffix("/") ? path : path + "/") { return false }
        }
        return !sources.allSatisfy { samePath($0.deletingLastPathComponent(), destination) }
    }

    nonisolated private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    nonisolated private static func samePath(_ a: URL, _ b: URL) -> Bool {
        canonicalPath(a) == canonicalPath(b)
    }
}
