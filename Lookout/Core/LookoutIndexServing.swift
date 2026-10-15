import Foundation

/// The XPC interface of `LookoutIndexService`, the indexer embedded in DOKK.app: it keeps the index in step with the
/// chosen folders and embeds what's new, then exits about a minute after it runs out of work, which returns the
/// model's memory (about 1 GB). The next message relaunches it.
///
/// The service is the index's only writer. It never asks for folder access: a folder it can't read is reported in
/// `LookoutIndexStatus.notPermittedRoots` and skipped until the next `start` or `syncNow`.
///
/// Messages on one connection arrive in order. A relaunched service knows nothing, so after a connection is
/// interrupted the app sends `pause()` first if indexing is paused, then `start(configuration:reply:)` again.
///
/// The protocol is `nonisolated` so it stays callable from NSXPC's own queues when the app compiles it with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Replies arrive on an arbitrary queue.
@objc nonisolated protocol LookoutIndexServing {
    /// Opens the index and starts work: a sync of the folders, then indexing as the power policy allows. A later call
    /// replaces the configuration (folders added or removed, other exclusions) and syncs again; files under none of
    /// the folders leave the index.
    ///
    /// - Parameters:
    ///   - configuration: A JSON-encoded `LookoutIndexConfiguration` (`LookoutIndexConfiguration.encoded()`).
    ///   - reply: Nil once the configuration is accepted (work goes on afterwards), or why it wasn't (it can't be
    ///     decoded). Problems with the index itself arrive as a `failed` status.
    func start(configuration: Data, reply: @escaping @Sendable (String?) -> Void)

    /// Something changed in the folders (the app's FSEvents watcher): sync, then index what the sync queued.
    func syncNow()

    /// Whether the backfill (everything but a few new files) may run: the app's power policy. Up to 50 files a sync
    /// finds index whatever this says.
    func setBackfillAllowed(_ allowed: Bool)

    /// Stops after the file being read, frees the model and does no more work until `resume()`.
    func pause()

    /// Undoes `pause()` and picks up where indexing stopped.
    func resume()

    /// The latest status, as a JSON-encoded `LookoutIndexStatus`.
    func currentStatus(reply: @escaping @Sendable (Data) -> Void)

    /// "Read everything again": queues every file once more (`IndexStore.resetAll`), drops their vectors and syncs.
    /// File names stay searchable meanwhile. Needs a configuration (`start`) first; without one it does nothing.
    func resetIndex()

    /// Stops work after the file being read, frees the model, closes the index and forgets the configuration, so
    /// the app can delete `index.sqlite` without this process writing to the deleted file afterwards. A later `start`
    /// opens the index again (a new, empty one if it was deleted).
    ///
    /// - Parameter reply: Called once the index is closed.
    func closeIndex(reply: @escaping @Sendable () -> Void)
}

/// What the app exports on the index service's connection, so the service can report progress.
@objc nonisolated protocol LookoutIndexClient {
    /// A new status, JSON-encoded (`LookoutIndexStatus.decode`). Sent at most about ten times a second; the latest
    /// one always arrives.
    func indexStatusDidChange(_ status: Data)
}
