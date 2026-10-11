import Foundation
import os

/// The app's read side of the Lookout index: owns the read-only `IndexStore` and its `Searcher`, off the main actor.
///
/// SQLite's WAL lets this connection read while the index service writes, so a search never waits for indexing. The
/// actor serializes every use of the store and the searcher, which are not thread-safe.
///
/// - The store opens on first use, and again on every later call until the service has created the index: before
///   that `search` returns nil.
/// - Vectors load lazily (the first meaning search, or `prepareVectors`) and leave with `releaseVectors`.
/// - `indexDidChange` reloads loaded vectors at once if the last reload is at least `reloadInterval` old, else once
///   that interval is up (one trailing reload covers any number of changes in between). Released vectors aren't
///   touched: the next load reads them fresh.
actor LookoutIndexReader: LookoutIndexSearching {
    /// The shortest time between two reloads while the service keeps adding vectors.
    nonisolated static let reloadInterval: Duration = .seconds(2)

    private let directory: URL
    private var store: IndexStore?
    private var searcher: Searcher?
    private var lastReload: ContinuousClock.Instant?
    /// The index changed since the vectors were read.
    private var stale = false
    /// The pending trailing reload; cancelled when the vectors are released.
    private var trailingReload: Task<Void, Never>?

    /// - Parameter directory: The folder `index.sqlite` is in (`LookoutPaths.index`).
    init(directory: URL) {
        self.directory = directory
    }

    func search(_ request: LookoutSearchRequest) throws -> LookoutResultSet? {
        guard let searcher = try openIfNeeded() else { return nil }
        let wasLoaded = searcher.vectorsLoaded
        // The index stores real paths (/private/var, not /var), as the crawl reports them.
        let scope = request.scope.map { FolderSelection.realPath(($0 as NSString).standardizingPath) }
        let results = try searcher.search(request.text, queryVector: request.vector, scope: scope,
                                          kinds: request.kinds, filter: request.filter, limit: request.limit,
                                          prefixLast: request.prefixLast)
        if !wasLoaded, searcher.vectorsLoaded { didReload() }
        return results
    }

    func prepareVectors() {
        guard let searcher = try? openIfNeeded(), !searcher.vectorsLoaded else { return }
        do {
            try searcher.reload()
            didReload()
        } catch {
            LookoutLog.logger.error("Can't load Lookout vectors: \(String(describing: error), privacy: .public)")
        }
    }

    func releaseVectors() {
        trailingReload?.cancel()
        trailingReload = nil
        stale = false
        searcher?.releaseVectors()
    }

    func indexDidChange() {
        guard let searcher = try? openIfNeeded(), searcher.vectorsLoaded else { return }
        stale = true
        guard trailingReload == nil else { return }
        let elapsed = lastReload.map { ContinuousClock.now - $0 } ?? Self.reloadInterval
        guard elapsed < Self.reloadInterval else { return reloadIfStale() }
        let wait = Self.reloadInterval - elapsed
        trailingReload = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.trailingReloadFired()
        }
    }

    private func trailingReloadFired() {
        trailingReload = nil
        reloadIfStale()
    }

    private func reloadIfStale() {
        guard stale, let searcher, searcher.vectorsLoaded else { return }
        do {
            try searcher.reload()
            didReload()
        } catch {
            LookoutLog.logger.error("Can't reload Lookout vectors: \(String(describing: error), privacy: .public)")
        }
    }

    private func didReload() {
        lastReload = .now
        stale = false
    }

    /// The searcher, opening the index read-only first if it's there now.
    private func openIfNeeded() throws -> Searcher? {
        if let searcher { return searcher }
        guard let store = try IndexStore.openReadOnly(directory: directory) else { return nil }
        let searcher = try Searcher(store: store, loadVectors: false)
        self.store = store
        self.searcher = searcher
        return searcher
    }
}
