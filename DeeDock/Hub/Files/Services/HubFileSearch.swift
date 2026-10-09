import Foundation
import Observation

/// Spotlight file-name search for the Files tab.
///
/// Each `search` restarts a 150 ms debounce; the previous query, debounce, and conversion are
/// cancelled, and a generation token drops any result that arrives late. Gathering stops at 200
/// hits (the query does not stay live), then results are ranked: names starting with the query
/// first, then most recently used or modified.
@MainActor @Observable
final class HubFileSearch {
    /// Where to search.
    nonisolated enum Scope: Hashable, Sendable {
        case thisMac
        case folder(URL)
    }

    /// Ranked results for the latest query. Empty for an empty query.
    private(set) var results: [HubFileItem] = []
    /// True from the debounce until ranked results are published.
    private(set) var isSearching = false

    static let limit = 200
    static let debounce: Duration = .milliseconds(150)

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    nonisolated init() {}

    /// Searches file names containing `query` (case and diacritic insensitive) within `scope`.
    func search(_ text: String, scope: Scope) {
        cancelRunning()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let token = generation
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.startQuery(text, scope: scope, token: token)
        }
    }

    /// Stops any search in progress and keeps the current results.
    func stop() {
        cancelRunning()
        isSearching = false
    }

    /// The `LIKE` pattern for a name containing `text`. Escapes `\`, `*`, and `?`, which `LIKE`
    /// treats as wildcards, so a query such as "a*b" matches literally.
    nonisolated static func likePattern(for text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "*" || character == "?" { escaped.append("\\") }
            escaped.append(character)
        }
        return "*\(escaped)*"
    }

    /// Prefix matches first, then the most recently used (or modified) item, then by name.
    nonisolated static func rank(_ found: [(item: HubFileItem, lastUsed: Date?)], query: String) -> [HubFileItem] {
        func isPrefix(_ item: HubFileItem) -> Bool {
            item.name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }
        return found.sorted { a, b in
            let (pa, pb) = (isPrefix(a.item), isPrefix(b.item))
            if pa != pb { return pa }
            let da = a.lastUsed ?? a.item.modified ?? .distantPast
            let db = b.lastUsed ?? b.item.modified ?? .distantPast
            if da != db { return da > db }
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }.map(\.item)
    }

    private func startQuery(_ text: String, scope: Scope, token: UUID) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, Self.likePattern(for: text))
        switch scope {
        case .thisMac: query.searchScopes = [NSMetadataQueryLocalComputerScope]
        case .folder(let url): query.searchScopes = [url]
        }
        query.notificationBatchingInterval = 0.1
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: query,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, let query = self.query,
                      query.resultCount >= Self.limit else { return }
                self.gathered(query, text: text, token: token)
            }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, let query = self.query else { return }
                self.gathered(query, text: text, token: token)
            }
        })
        self.query = query
        query.start()
    }

    private func gathered(_ query: NSMetadataQuery, text: String, token: UUID) {
        guard self.query === query else { return }
        let hits = HubMetadataResults.hits(from: query, limit: Self.limit)
        tearDownQuery()
        pending = Task { [weak self] in
            let found = await HubMetadataResults.items(for: hits)
            let ranked = Self.rank(found, query: text)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.results = ranked
            self.isSearching = false
        }
    }

    private func cancelRunning() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        tearDownQuery()
    }

    private func tearDownQuery() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query?.stop()
        query = nil
    }

    isolated deinit { cancelRunning() }
}
