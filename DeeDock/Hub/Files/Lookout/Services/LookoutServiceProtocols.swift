import Foundation

/// The index service as `LookoutEngine` drives it. The live one is `LookoutIndexConnection` (XPC); tests use fakes.
///
/// The service exits by itself about a minute after it runs out of work, and a relaunched service knows nothing.
/// Implementations remember the last configuration and pause state and replay them before the next message that needs
/// the service, so callers never resend them. Callbacks arrive on the main actor.
@MainActor protocol LookoutIndexControlling: AnyObject {
    /// Each status the service reports.
    var onStatus: ((LookoutIndexStatus) -> Void)? { get set }
    /// The service went away or can't be reached.
    var onConnectionEvent: ((LookoutIndexConnectionEvent) -> Void)? { get set }
    /// True while a service process is believed to hold the configuration: from `start` until the connection is
    /// interrupted or invalidated.
    var isServiceRunning: Bool { get }

    /// Sends a new configuration, launching the service if needed: it prunes everything outside the roots and syncs.
    func start(_ configuration: LookoutIndexConfiguration)
    /// Asks for a sync. Relaunches the service with the last configuration (which syncs) when it isn't running.
    func syncNow()
    /// Records the power policy's verdict and tells a running service. A service that isn't running isn't launched
    /// for it: the next `start` carries it.
    func setBackfillAllowed(_ allowed: Bool)
    /// Pauses a running service; the pause is replayed before any later relaunch.
    func pause()
    /// Undoes `pause`, relaunching the service when it isn't running.
    func resume()
    /// Drops the connection for good (the engine stopped). A later `start` opens a new one.
    func invalidate()
    /// "Read everything again": the service queues every file again and syncs. Relaunches it with the last
    /// configuration first when it isn't running; does nothing before the first `start`.
    func resetIndex()
    /// Asks the service to close the index (`LookoutIndexServing.closeIndex`) and waits, at most `timeout`, for its
    /// confirmation that the store and the model are closed. The request goes out even when no service is known to
    /// run, because a process from before a relaunch of DOKK may still hold the store. Requests that could open the
    /// index again (a configuration, a relaunch) wait until the call ends.
    ///
    /// - Throws: `LookoutIndexCloseError` when the service didn't confirm. Nothing may be deleted then, and the
    ///   remembered configuration is sent again so Lookout goes on as before.
    func closeIndex(timeout: Duration) async throws
}

/// The index service didn't confirm that it closed the index (`LookoutIndexControlling.closeIndex`).
nonisolated enum LookoutIndexCloseError: Error, Equatable {
    /// No confirmation within the time limit: a batch may still be committing.
    case timedOut
    /// The call failed: the service couldn't be reached, or went away before answering.
    case unavailable
}

/// Why the index service's connection changed.
nonisolated enum LookoutIndexConnectionEvent: Sendable, Equatable {
    /// The process ended (idle exit or crash). The next message relaunches it.
    case interrupted
    /// The service can't be reached (not embedded, or launchd refused it).
    case unavailable
}

/// The query encoder as search uses it. The live one is `LookoutQueryEncoder` (XPC); tests use fakes.
@MainActor protocol LookoutQueryEncoding: AnyObject {
    /// True after a successful call to a service process that is still running: the next embed takes milliseconds.
    /// False after launch, an interruption, or a failure, when the next call pays the cold start (about 0.4 s, and
    /// about 5 s the first time after an install while Metal compiles its shaders).
    var isWarm: Bool { get }
    /// Loads the model now, so the first query doesn't wait for it.
    ///
    /// - Throws: `LookoutEncoderError`.
    func warmUp() async throws
    /// The query's vector: `Prompts.query(query)` embedded, 768 L2-normalized floats.
    ///
    /// - Throws: `LookoutEncoderError`, or `CancellationError` when the calling task is cancelled.
    func embed(query: String) async throws -> [Float]
    /// Drops the connection (the engine stopped).
    func invalidate()
}

/// What `LookoutSearch` asks the index reader for.
nonisolated struct LookoutSearchRequest: Sendable, Equatable {
    var text: String
    /// Nil for the keyword-only first pass.
    var vector: [Float]?
    /// A folder to search inside, or nil for the whole index.
    var scope: String?
    var kinds: Set<FileKind>?
    var filter: LookoutSearchFilter?
    var prefixLast: Bool
    var limit = 40
}

/// The read side of the index: owns the read-only store and the `Searcher` off the main actor. The live one is
/// `LookoutIndexReader`.
nonisolated protocol LookoutIndexSearching: Sendable {
    /// Searches, opening the index first if it has appeared since the last call.
    ///
    /// - Returns: The results, or nil while there's no index to read yet.
    /// - Throws: SQLite errors.
    func search(_ request: LookoutSearchRequest) async throws -> LookoutResultSet?
    /// Loads the vectors ahead of the first meaning search (the Files tab appeared).
    func prepareVectors() async
    /// Frees the vectors (the Hub has been closed for a while). Keyword search keeps working.
    func releaseVectors() async
    /// The index service changed the stored vectors (`LookoutIndexStatus.vectorsChangedAt`): reload loaded vectors,
    /// at most every 2 s.
    func indexDidChange() async
    /// Closes the read-only store and drops the vectors, before the index files are deleted. The next search opens
    /// the index again once the service has made a new one.
    func closeIndex() async
    /// For each folder (absolute paths, as Settings lists them), how many files under it have something to find
    /// besides their name. Empty while there's no index to read.
    func searchableFileCounts(under folders: [String]) async -> [String: Int]
}

/// What the monitor reports.
nonisolated enum LookoutMonitorEvent: Sendable, Equatable {
    /// Files changed in a watched folder (FSEvents).
    case foldersChanged
    /// A drive was mounted or ejected: a missing folder may be back, or gone.
    case volumesChanged
    /// The Mac woke from sleep.
    case didWake
}

/// File-system and system events that should make the index service sync. The live one is `LookoutMonitor`.
@MainActor protocol LookoutMonitoring: AnyObject {
    /// Starts watching `roots` (the ones that are there now) and the system.
    func start(roots: [String], onEvent: @escaping (LookoutMonitorEvent) -> Void)
    /// Watches `roots` instead: the folders changed, or a drive came back.
    func watch(roots: [String])
    /// Stops everything and drops `onEvent`.
    func stop()
}

/// Why the backfill (everything but a few new files) has to wait.
nonisolated enum LookoutBackfillBlocker: String, Sendable, Equatable {
    case lowPowerMode
    /// Thermal state serious or critical.
    case warm
    /// On battery with "Read files on battery too" off.
    case onBattery
}

/// The power policy as the engine uses it. The live one is `LookoutPowerPolicy`.
@MainActor protocol LookoutPowerPolicing: AnyObject {
    /// Why the backfill waits now, or nil when it may run.
    var blocker: LookoutBackfillBlocker? { get }
    /// Starts observing; `onChange` hears each new verdict.
    func start(indexOnBattery: Bool, onChange: @escaping (LookoutBackfillBlocker?) -> Void)
    func setIndexOnBattery(_ indexOnBattery: Bool)
    func stop()
}
