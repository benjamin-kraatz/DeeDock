import AppKit
import OSLog

/// Tracks applications that macOS 27 reports as running in background, and stops them.
///
/// Reads are event-driven, without polling. Workspace launch, termination, wake, and session
/// changes trigger a read. A process-exit source watches every remaining process and triggers
/// a read when one exits, so a tile drops its background state as soon as its last process
/// ends. Reads are coalesced, and a read requested during another runs once afterwards.
///
/// The feature is fail-closed. When `LaunchServicesBackgroundReader` is unavailable, the
/// monitor publishes no applications, stops observing, and offers nothing to stop. Failures
/// are logged, never shown. Owners call `stop()` to remove observers, sources, and tasks.
@MainActor
final class BackgroundApplicationMonitor {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "BackgroundApps")

    /// A Launch Services read. It blocks, so the monitor runs it on a private queue.
    typealias Read = @Sendable () -> Result<[BackgroundApplication], LaunchServicesBackgroundReader.Unavailability>

    /// How long a process may handle SIGTERM before it is killed.
    let terminationGrace: Duration

    /// Background applications keyed by standardized bundle URL.
    private(set) var applications: [URL: BackgroundApplication] = [:]
    /// Set once the reader reports that it cannot work on this system.
    private(set) var unavailability: LaunchServicesBackgroundReader.Unavailability?
    /// Called on the main actor after `applications` changes.
    var didChange: (() -> Void)?
    /// Called once when the reader turns out to be unavailable.
    var didBecomeUnavailable: ((LaunchServicesBackgroundReader.Unavailability) -> Void)?

    private let reads: BackgroundApplicationReads
    private var observers: [NSObjectProtocol] = []
    private var exitSources: [BackgroundProcess: any DispatchSourceProcess] = [:]
    private var readTask: Task<Void, Never>?
    private var needsAnotherRead = false
    /// Counts reads that have started; a waiter is answered only by a read started after it.
    private var readsStarted = 0
    private var waiters: [UUID: Waiter] = [:]
    private var stopTasks: [URL: StopTask] = [:]

    /// A caller of `refreshAndWait` and the first read whose result can answer it.
    private struct Waiter {
        let firstAnsweringRead: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    /// A pending stop. The ID lets a finished task remove only its own entry.
    private struct StopTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// - Parameters:
    ///   - read: Reads Launch Services. Tests pass a fake; production uses the private reader.
    ///   - terminationGrace: How long a process may handle SIGTERM before it is killed.
    init(read: @escaping Read = { LaunchServicesBackgroundReader.read() }, terminationGrace: Duration = .seconds(3)) {
        reads = BackgroundApplicationReads(read: read)
        self.terminationGrace = terminationGrace
    }

    /// Starts observing and performs the first read. Calling it again has no effect.
    func start() {
        guard observers.isEmpty, unavailability == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.applicationDidLaunch(at: app?.bundleURL)
            }
        })
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    /// Cancels a pending stop for an app that has just been opened, then reads.
    ///
    /// The new instance may use the helpers the stop was about to end, and if it quits again
    /// before the grace period is over, the helpers it leaves are not the ones the user asked to
    /// stop. Cancelling the task ends that stop for good, so a quick reopen and quit cannot
    /// revive its SIGKILL pass.
    func applicationDidLaunch(at url: URL?) {
        if let url = url?.standardizedFileURL, let pending = stopTasks.removeValue(forKey: url) {
            pending.task.cancel()
            Self.logger.info("Cancelled a pending stop because the app was opened again")
        }
        refresh()
    }

    /// Removes observers and exit sources and cancels reads and pending stops.
    func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        exitSources.values.forEach { $0.cancel() }
        exitSources.removeAll()
        readTask?.cancel()
        readTask = nil
        needsAnotherRead = false
        stopTasks.values.forEach { $0.task.cancel() }
        stopTasks.removeAll()
        resumeWaiters(answeredBy: .max)
    }

    /// The background application for `url`, if its bundle has no running main process.
    func application(at url: URL) -> BackgroundApplication? {
        applications[url.standardizedFileURL]
    }

    /// Requests a read. Coalesces with a read already in flight.
    func refresh() {
        guard unavailability == nil else { return }
        guard readTask == nil else {
            needsAnotherRead = true
            return
        }
        readsStarted += 1
        let number = readsStarted
        readTask = Task { [weak self, reads] in
            let result = await reads.read()
            guard let self, !Task.isCancelled else { return }
            readTask = nil
            // `apply` can start the next read synchronously, through `watch` or `didChange`.
            // The number keeps that read's waiters from being answered by this one.
            apply(result)
            resumeWaiters(answeredBy: number)
            if needsAnotherRead {
                needsAnotherRead = false
                refresh()
            }
        }
    }

    /// Reads and returns once that read is applied, or after `timeout`, whichever is first.
    ///
    /// When an app quits, the workspace notification arrives before DOKK has read the app's
    /// background record. A caller that waits here can publish both changes at once, so a
    /// tile that stays as a background app never disappears and reappears in between. A read
    /// already in flight may have started before the caller's event, so this waits for a read
    /// that starts after the call. The timeout bounds the wait if Launch Services stalls.
    /// Returns immediately while the reader is unavailable.
    func refreshAndWait(timeout: Duration) async {
        guard unavailability == nil else { return }
        let id = UUID()
        await withCheckedContinuation { continuation in
            // Any read in flight started earlier, so only the next read to start can answer.
            waiters[id] = Waiter(firstAnsweringRead: readsStarted + 1, continuation: continuation)
            refresh()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.waiters.removeValue(forKey: id)?.continuation.resume()
            }
        }
    }

    /// Resumes, exactly once, every waiter that read `number` answers. Removing a waiter
    /// before resuming it keeps its timeout from resuming it a second time.
    private func resumeWaiters(answeredBy number: Int) {
        let answered = waiters.filter { $0.value.firstAnsweringRead <= number }
        for id in answered.keys { waiters[id] = nil }
        answered.values.forEach { $0.continuation.resume() }
    }

    /// Ends every remaining process of the background application at `url`.
    ///
    /// Each pass re-reads Launch Services, so it signals only processes that currently belong
    /// to that app, including helpers started after the first pass. Sends SIGTERM, waits
    /// `terminationGrace`, then sends SIGKILL to whatever remains. Opening the app cancels the
    /// stop (see `applicationDidLaunch(at:)`), and neither pass signals while a regular instance
    /// runs, because it may use the same helpers. A failed read turns the feature off for the
    /// session, as any other read failure does. Failures are silent: the tile keeps its
    /// background state until the processes actually exit.
    func stopRunningInBackground(at url: URL) {
        let url = url.standardizedFileURL
        guard unavailability == nil, stopTasks[url] == nil else { return }
        let id = UUID()
        let task = Task { [weak self] in
            await self?.performStop(at: url)
            // A launch may already have cancelled and removed this entry, and a newer stop may
            // own the key by now; only this stop's own entry is cleared.
            if self?.stopTasks[url]?.id == id { self?.stopTasks[url] = nil }
        }
        stopTasks[url] = StopTask(id: id, task: task)
    }

    private func performStop(at url: URL) async {
        guard let terminated = await signal(SIGTERM, backgroundApplicationAt: url) else { return }
        if terminated > 0 {
            Self.logger.info("Sent SIGTERM to \(terminated, privacy: .public) background processes")
            try? await Task.sleep(for: terminationGrace)
            guard !Task.isCancelled,
                  let killed = await signal(SIGKILL, backgroundApplicationAt: url) else { return }
            if killed > 0 {
                Self.logger.info("Sent SIGKILL to \(killed, privacy: .public) background processes after the grace period")
            }
        }
        // `stop()` and a launch cancel this task; a read after teardown would recreate exit sources.
        guard !Task.isCancelled else { return }
        refresh()
    }

    /// Signals the processes that belong to the app in two consecutive reads. Returns how many
    /// signals the kernel delivered, or `nil` when the pass was cancelled or a read failed.
    ///
    /// A read captures each listed process's identity just after Launch Services lists its PID.
    /// If that PID was reused in between, the captured identity belongs to an unrelated process,
    /// which is not in the app's coalition, so the second read cannot list it. Only identities
    /// in both reads are signalled, and the kernel delivers each signal only to that exact
    /// process instance (see `BackgroundProcess.send(_:)`).
    private func signal(_ signal: Int32, backgroundApplicationAt url: URL) async -> Int? {
        var listings: [Set<BackgroundProcess>] = []
        for _ in 0..<2 {
            let result = await reads.read()
            guard !Task.isCancelled else { return nil }
            switch result {
            case .failure(let reason):
                apply(.failure(reason))
                return nil
            case .success(let current):
                listings.append(Set(current.first { $0.bundleURL == url }?.processes ?? []))
            }
        }
        guard !Self.hasRunningInstance(of: url) else { return 0 }
        return listings[0].intersection(listings[1]).filter { $0.send(signal) }.count
    }

    private func apply(_ result: Result<[BackgroundApplication], LaunchServicesBackgroundReader.Unavailability>) {
        switch result {
        case .failure(let reason):
            // A stop pass and a refresh can both fail; the session turns off, and reports it, once.
            guard unavailability == nil else { return }
            Self.logger.notice("Background application reading is off: \(reason.rawValue, privacy: .public)")
            stop()
            unavailability = reason
            publish([:])
            didBecomeUnavailable?(reason)
        case .success(let list):
            let ownBundle = Bundle.main.bundleURL.standardizedFileURL
            var next: [URL: BackgroundApplication] = [:]
            for application in list where application.bundleURL != ownBundle {
                next[application.bundleURL] = application
            }
            watch(Set(next.values.flatMap(\.processes)))
            publish(next)
        }
    }

    private func publish(_ next: [URL: BackgroundApplication]) {
        guard next != applications else { return }
        applications = next
        didChange?()
    }

    /// Keeps exactly one exit source per remaining process.
    ///
    /// A process can exit between the read and the source's creation; kqueue then never
    /// delivers the exit. The identity check after `resume()` catches that case and reads again.
    private func watch(_ processes: Set<BackgroundProcess>) {
        for (process, source) in exitSources where !processes.contains(process) {
            source.cancel()
            exitSources[process] = nil
        }
        var missedExit = false
        for process in processes where exitSources[process] == nil {
            let source = DispatchSource.makeProcessSource(identifier: process.pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.exitSources.removeValue(forKey: process)?.cancel()
                    self?.refresh()
                }
            }
            source.resume()
            exitSources[process] = source
            if !process.isStillRunning { missedExit = true }
        }
        if missedExit { refresh() }
    }

    private static func hasRunningInstance(of url: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url }
    }
}

/// Runs Launch Services reads on a private serial queue.
///
/// Each read is a few milliseconds of blocking IPC. A private queue keeps it off the main
/// actor and out of the cooperative pool, as `BadgeAXSession` does for Accessibility reads.
private nonisolated final class BackgroundApplicationReads: Sendable {
    private let queue = DispatchQueue(label: "DeeDock.BackgroundAppReads", qos: .utility)
    private let reader: BackgroundApplicationMonitor.Read

    init(read: @escaping BackgroundApplicationMonitor.Read) { reader = read }

    func read() async -> Result<[BackgroundApplication], LaunchServicesBackgroundReader.Unavailability> {
        await withCheckedContinuation { continuation in
            queue.async { [reader] in continuation.resume(returning: reader()) }
        }
    }
}
