import Foundation
import Observation
import os

/// Lookout's content search for the Files tab, beside the name-only Spotlight search (`HubFileSearch`), which stays
/// separate: the UI shows both, and Spotlight's names never wait for Lookout.
///
/// Each `search` restarts a short debounce and cancels the previous query's work; a generation token drops anything
/// that arrives late, so a stale result never publishes. After the debounce, two things start at once:
///
/// 1. The keyword part runs on the index reader (the last word as a prefix, since it's probably half-typed) and
///    publishes keyword-only results (`Phase.keywordOnly`, or `.warming` while the encoder is cold).
/// 2. The query encoder embeds the query; with its vector the hybrid search runs and publishes the final results
///    (`.done`). If the encoder fails, the final results are keyword-only (`results.usedMeaning` is false).
///
/// `LookoutEngine` owns this, and sets `isAvailable` and `filter` from the settings.
@MainActor @Observable
final class LookoutSearch {
    /// Where the latest query is.
    enum Phase: Equatable, Sendable {
        /// No query.
        case idle
        /// Meaning waits for the query encoder's cold start (about 0.4 s, or about 5 s once after an install while
        /// Metal compiles shaders). Keyword results may already show.
        case warming
        /// Keyword results show; meaning is on its way.
        case keywordOnly
        /// The final results for the query.
        case done
        /// Lookout can't search: it's off or not set up, or there's no index yet.
        case unavailable
    }

    nonisolated static let debounce: Duration = .milliseconds(150)

    private(set) var phase: Phase = .idle
    /// The latest results, empty for an empty query.
    private(set) var results: LookoutResultSet = .empty

    /// Whether Lookout is set up and on. Turning it off cancels the search and clears the results; turning it on
    /// re-runs the last query.
    var isAvailable = false {
        didSet {
            guard isAvailable != oldValue else { return }
            if isAvailable { refresh() } else { becomeUnavailable() }
        }
    }

    /// Which files the settings allow (`LookoutSearchFilter`); nil shows everything indexed.
    @ObservationIgnored var filter: LookoutSearchFilter?

    @ObservationIgnored private let reader: any LookoutIndexSearching
    @ObservationIgnored private let encoder: any LookoutQueryEncoding
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    /// The last non-empty query, for `refresh`.
    @ObservationIgnored private var last: (text: String, scope: HubFileSearch.Scope, kinds: Set<FileKind>?)?

    /// - Parameters:
    ///   - reader: The index's read side (`LookoutIndexReader`).
    ///   - encoder: The query encoder (`LookoutQueryEncoder`).
    ///   - debounce: The pause after the last keystroke before searching.
    init(reader: any LookoutIndexSearching, encoder: any LookoutQueryEncoding, debounce: Duration = LookoutSearch.debounce) {
        self.reader = reader
        self.encoder = encoder
        self.debounce = debounce
    }

    /// Searches file contents for `text` within `scope`.
    ///
    /// - Parameters:
    ///   - text: What was typed; surrounding whitespace is ignored, and an empty query clears the results.
    ///   - scope: "This Mac" searches the whole index; a folder searches the files under it.
    ///   - kinds: Only these kinds of file; nil for all.
    func search(_ text: String, scope: HubFileSearch.Scope, kinds: Set<FileKind>? = nil) {
        cancelRunning()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            last = nil
            results = .empty
            phase = .idle
            return
        }
        last = (text, scope, kinds)
        guard isAvailable else {
            results = .empty
            phase = .unavailable
            return
        }
        let request = LookoutSearchRequest(text: text, vector: nil, scope: scope.lookoutFolder, kinds: kinds,
                                           filter: filter, prefixLast: true)
        if !encoder.isWarm { phase = .warming }
        let token = generation
        let debounce = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard let self, self.isCurrent(token) else { return }
            await self.run(request, token: token)
        }
    }

    /// Stops the search in progress, keeping the latest results and phase. A later `search` starts over.
    func stop() {
        cancelRunning()
    }

    /// Runs the last query again (the index appeared, or Lookout came back on).
    func refresh() {
        guard let last else { return }
        search(last.text, scope: last.scope, kinds: last.kinds)
    }

    // MARK: Running

    private func run(_ request: LookoutSearchRequest, token: UUID) async {
        let reader = reader
        let encoder = encoder
        // Meaning starts now, beside the keyword pass. Cancelling `pending` cancels this child too.
        async let vector = encoder.embed(query: request.text)

        let keyword: LookoutResultSet?
        do {
            keyword = try await reader.search(request)
        } catch {
            LookoutLog.logger.error("Lookout keyword search failed: \(String(describing: error), privacy: .public)")
            keyword = nil
        }
        guard isCurrent(token) else { return }
        guard let keyword else {
            results = .empty
            phase = .unavailable
            return
        }
        results = keyword
        phase = encoder.isWarm ? .keywordOnly : .warming

        let queryVector = try? await vector
        guard isCurrent(token) else { return }
        var hybrid = request
        hybrid.vector = queryVector
        hybrid.prefixLast = false
        let final = try? await reader.search(hybrid)
        guard isCurrent(token) else { return }
        results = final ?? keyword
        phase = .done
    }

    private func isCurrent(_ token: UUID) -> Bool {
        !Task.isCancelled && generation == token
    }

    private func becomeUnavailable() {
        cancelRunning()
        results = .empty
        phase = last == nil ? .idle : .unavailable
    }

    private func cancelRunning() {
        generation = UUID()
        pending?.cancel()
        pending = nil
    }

    isolated deinit { cancelRunning() }
}

extension HubFileSearch.Scope {
    /// The folder Lookout limits a search to, or nil for the whole index.
    nonisolated var lookoutFolder: String? {
        switch self {
        case .thisMac: nil
        case .folder(let url): url.path
        }
    }
}
