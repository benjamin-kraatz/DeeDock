import Foundation
import Observation
import os

/// Lookout's search with a picture: a dropped or pasted picture, or Find Similar on a file in the index, alone or with
/// words typed beside it.
///
/// A new picture is read in the app (`LookoutPictureReading`), sent to the query service as pixels, and its vector
/// searched with (`Searcher.similar`). The service loads its picture reader only for the first picture; the phases say
/// so honestly: `.waking` while it loads, `.reading` while the picture is encoded. A file in the index reuses its
/// stored vector, so its results arrive at once and the reader isn't touched.
///
/// Each `search` cancels the previous one's work, and a generation token drops anything that arrives late. The last
/// vector is kept in memory while its search is current, so a scope change searches again without reading the
/// picture again; `clear()` drops it. Nothing is written anywhere.
///
/// Words typed beside the picture (`updateWords`) are embedded by the query service as a search by words is, after the
/// same short debounce, and searched with together with the picture's vector, which is reused: typing never reads the
/// picture again. Words typed while the picture is still being read wait for it. Their vector is kept for the text it
/// was made from, so moving the picture–words slider (`setWordsWeight`) only ranks again.
///
/// The current request is kept until `clear()`, so a search that couldn't run, or ran under old settings, runs
/// again by itself: when Lookout becomes available (set up, or turned on again), and through `refresh()` when the
/// settings' filter changes or the index first appears. A refresh reuses the vector when there is one.
///
/// `LookoutEngine` owns this and sets `isAvailable` and `filter` from the settings. Main actor.
@MainActor @Observable
final class LookoutPictureSearch {
    nonisolated enum Phase: Equatable, Sendable {
        /// No picture.
        case idle
        /// Find Similar is reading a file's stored vector from the index (a moment; nothing is encoded).
        case lookingUp
        /// The picture reader is loading in the query service (the first picture since it started).
        case waking
        /// The picture is being encoded.
        case reading
        /// The results for the picture.
        case done
        /// The picture couldn't be read or encoded.
        case failed
        /// Lookout can't search: it's off or not set up, or there's no index yet.
        case unavailable
    }

    private(set) var phase: Phase = .idle
    /// The latest results; empty groups until they arrive.
    private(set) var results = LookoutSimilarResults(queryIsPicture: true)
    /// How long the picture took to read, wake-up included, for "read in 0.4 s". Nil for a stored vector.
    private(set) var readSeconds: Double?
    /// The stored vector searched with, when Find Similar reused one (its page, for "Page 7").
    private(set) var storedSource: LookoutSimilarSource?
    /// The words typed beside the picture, trimmed; empty for none.
    private(set) var words = ""
    /// How much the words count against the picture, within `LookoutRanking.pictureWordsWeights`. Back to
    /// `LookoutRanking.pictureWordsWeight` for every new picture.
    private(set) var wordsWeight = LookoutRanking.pictureWordsWeight

    /// Whether Lookout is set up and on. Turning it off cancels the search and clears the results; turning it on
    /// runs the current request, which couldn't run meanwhile, again.
    var isAvailable = false {
        didSet {
            guard isAvailable != oldValue else { return }
            if !isAvailable, phase != .idle {
                cancelRunning()
                results = LookoutSimilarResults(queryIsPicture: results.queryIsPicture)
                phase = .unavailable
            } else if isAvailable, phase == .unavailable {
                refresh()
            }
        }
    }

    /// Which files the settings allow; nil shows everything indexed.
    @ObservationIgnored var filter: LookoutSearchFilter?

    @ObservationIgnored private let reader: any LookoutIndexSearching
    @ObservationIgnored private let encoder: any LookoutQueryEncoding
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    /// The current search's vector and what it excludes, for `rescope` and for searching again with new words.
    @ObservationIgnored private var current: (vector: [Float], isPicture: Bool, excluding: Set<String>)?
    /// The last words embedded and their vector, so the slider and a scope change don't embed them again.
    @ObservationIgnored private var wordsVector: (text: String, vector: [Float])?
    /// `lookout_picture_words_added` was counted for `request`'s picture.
    @ObservationIgnored private var wordsCounted = false
    /// Counts an analytics counter; `Analytics.count` unless a test listens.
    @ObservationIgnored var countAnalytics: (AnalyticsCounter) -> Void = { Analytics.count($0) }
    /// What was last searched with, until `clear()`, so `refresh()` can run it again.
    @ObservationIgnored private var request: (input: LookoutPictureInput, source: AnalyticsLookoutImageSource,
                                              scope: HubFileSearch.Scope)?
    /// The picture `request` is for (`LookoutPictureQuery.id`), when the caller says.
    @ObservationIgnored private var requestID: UUID?
    /// `lookout_image_search` was sent for `request`'s picture: a search that runs again for the same picture (a
    /// restart, a refresh, a scope change while it was still being read) doesn't send it twice.
    @ObservationIgnored private var requestTracked = false
    /// Sends an analytics event; `Analytics.track` unless a test listens.
    @ObservationIgnored var sendAnalytics: (AnalyticsEvent) -> Void = { Analytics.track($0) }

    init(reader: any LookoutIndexSearching, encoder: any LookoutQueryEncoding) {
        self.reader = reader
        self.encoder = encoder
    }

    /// Whether the next new picture has to wait for the picture reader to load.
    var isReaderCold: Bool { !encoder.isPictureReaderWarm }

    /// Searches with `input` within `scope`.
    ///
    /// - Parameters:
    ///   - source: Where the picture came from, for `lookout_image_search`.
    ///   - id: The picture searched with (`LookoutPictureQuery.id`). The same picture searched again, as a scope
    ///     change does while it's still being read, is the same request for analytics: `lookout_image_search` is
    ///     sent once, and the slider keeps its place. Nil is always a new request.
    ///   - words: Words typed beside the picture; empty for none.
    /// - Returns: Whether the search waits for the picture reader to load (it was cold).
    @discardableResult
    func search(_ input: LookoutPictureInput, source: AnalyticsLookoutImageSource,
                scope: HubFileSearch.Scope, id: UUID? = nil, words: String = "") -> Bool {
        if id == nil || id != requestID {
            requestTracked = false
            wordsCounted = false
            wordsWeight = LookoutRanking.pictureWordsWeight
        }
        request = (input, source, scope)
        requestID = id
        setWords(words)
        return start()
    }

    /// Runs `request` from the start.
    @discardableResult
    private func start() -> Bool {
        cancelRunning()
        current = nil
        readSeconds = nil
        storedSource = nil
        results = LookoutSimilarResults(queryIsPicture: true)
        guard let request else { return false }
        guard isAvailable else {
            phase = .unavailable
            return false
        }
        let token = generation
        let folder = request.scope.lookoutFolder
        let cold: Bool
        if case .indexed = request.input {
            cold = false
            phase = .lookingUp
        } else {
            cold = isReaderCold
            phase = cold ? .waking : .reading
            track(cold: cold)
        }
        let input = request.input
        pending = Task { [weak self] in
            await self?.run(input, folder: folder, token: token)
        }
        return cold
    }

    /// The current request again, under the current filter: a refresh with the vector it already has, or, when it
    /// couldn't run (Lookout wasn't available, or there was no index yet), from the start. A request still reading
    /// its picture is left alone: its results are built with the filter as it is when they come. The settings'
    /// filter changing and the index appearing call this.
    func refresh() {
        guard isAvailable, let request else { return }
        if current != nil {
            rescope(request.scope)
        } else if phase == .unavailable {
            start()
        }
    }

    /// `lookout_image_search`, once per request.
    private func track(cold: Bool) {
        guard !requestTracked, let request else { return }
        requestTracked = true
        sendAnalytics(LookoutAnalytics.imageSearch(source: request.source, cold: cold))
    }

    /// Searches the current picture again within a new scope, with the vector it already has.
    ///
    /// - Parameter words: The words typed beside the picture now; nil keeps the current ones (a refresh).
    /// - Returns: False when there's no vector yet (the picture was still being read): search again instead.
    @discardableResult
    func rescope(_ scope: HubFileSearch.Scope, words: String? = nil) -> Bool {
        guard current != nil, isAvailable else { return false }
        if let words { setWords(words) }
        request?.scope = scope
        searchAgain(after: .zero)
        return true
    }

    /// The words typed beside the picture changed: searches again with them and the picture's vector after the
    /// typing debounce (`LookoutSearch.debounce`). While the picture is still being read, they wait for it.
    func updateWords(_ words: String) {
        guard setWords(words), current != nil, isAvailable else { return }
        searchAgain(after: LookoutSearch.debounce)
    }

    /// Moves the picture–words slider: ranks again with both vectors as they are, after a moment's pause so a drag
    /// doesn't queue a search for every step.
    func setWordsWeight(_ weight: Double) {
        let range = LookoutRanking.pictureWordsWeights
        let weight = min(max(weight, range.lowerBound), range.upperBound)
        guard weight != wordsWeight else { return }
        wordsWeight = weight
        guard !words.isEmpty, current != nil, isAvailable else { return }
        searchAgain(after: Self.weightPause)
    }

    /// How long the slider waits for the next step before ranking again.
    nonisolated static let weightPause: Duration = .milliseconds(40)

    /// Takes `words` as the current words; counts the first words a picture gets.
    ///
    /// - Returns: Whether they changed.
    @discardableResult
    private func setWords(_ words: String) -> Bool {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words != self.words else { return false }
        self.words = words
        if !words.isEmpty, !wordsCounted, request != nil {
            wordsCounted = true
            countAnalytics(.lookoutPictureWordsAdded)
        }
        return true
    }

    /// Searches again with the vector the current search has, the current words, scope and filter, after `delay`.
    private func searchAgain(after delay: Duration) {
        guard let current, let request else { return }
        cancelRunning()
        let token = generation
        let similar = LookoutSimilarRequest(vector: current.vector, queryIsPicture: current.isPicture,
                                            excluding: current.excluding, scope: request.scope.lookoutFolder,
                                            filter: filter)
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, self.isCurrent(token) else { return }
            await self.finish(similar, token: token)
        }
    }

    /// Ends the search: cancels its work and forgets its vector and results.
    func clear() {
        cancelRunning()
        request = nil
        requestID = nil
        requestTracked = false
        wordsCounted = false
        words = ""
        wordsWeight = LookoutRanking.pictureWordsWeight
        wordsVector = nil
        current = nil
        readSeconds = nil
        storedSource = nil
        results = LookoutSimilarResults(queryIsPicture: true)
        phase = .idle
    }

    /// Loads the picture reader now (a picture is being dragged over the Hub), so the drop doesn't wait for it. Does
    /// nothing when it's warm, already loading, or Lookout can't search.
    func warmUp() {
        guard isAvailable, !encoder.isPictureReaderWarm, warmTask == nil else { return }
        let encoder = encoder
        warmTask = Task { [weak self] in
            do {
                try await encoder.warmUpPictureReader()
            } catch {
                LookoutLog.logger.info("Lookout picture reader warm-up failed: \(String(describing: error), privacy: .public)")
            }
            self?.warmTask = nil
        }
    }

    // MARK: Running

    private func run(_ input: LookoutPictureInput, folder: String?, token: UUID) async {
        let excluding = Set([input.excludedPath].compactMap { $0 })
        var toRead = input
        if case .indexed(let path, let segmentID, let fallback) = input {
            if let stored = await reader.similarSource(path: path, segmentID: segmentID) {
                guard isCurrent(token) else { return }
                // A stored vector reads nothing, so it never waits for the picture reader.
                track(cold: false)
                storedSource = stored
                current = (stored.vector, stored.modality == .image, excluding)
                await finish(LookoutSimilarRequest(vector: stored.vector, queryIsPicture: stored.modality == .image,
                                                   excluding: excluding, scope: folder, filter: filter), token: token)
                return
            }
            guard isCurrent(token) else { return }
            // Not in the index (or not read yet): a picture is read like a dropped one; anything else can't be.
            guard let fallback else { return fail(token) }
            toRead = .file(fallback)
            let cold = isReaderCold
            phase = cold ? .waking : .reading
            track(cold: cold)
        }
        let started = ContinuousClock.now
        let encoder = encoder
        do {
            // Read the picture while the reader wakes; both take a fraction of a second.
            let reading = toRead
            async let picture = Self.read(reading)
            if !encoder.isPictureReaderWarm {
                try await encoder.warmUpPictureReader()
                guard isCurrent(token) else { return }
                phase = .reading
            }
            let vector = try await encoder.embed(picture: try await picture)
            guard isCurrent(token) else { return }
            let elapsed = ContinuousClock.now - started
            readSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            current = (vector, true, excluding)
            await finish(LookoutSimilarRequest(vector: vector, queryIsPicture: true, excluding: excluding,
                                               scope: folder, filter: filter), token: token)
        } catch {
            guard isCurrent(token) else { return }
            LookoutLog.logger.error("Lookout can't search with a picture: \(String(describing: error), privacy: .public)")
            fail(token)
        }
    }

    private static func read(_ input: LookoutPictureInput) async throws -> QueryPicture {
        switch input {
        case .file(let url): try await LookoutPictureReading.picture(at: url)
        case .data(let data): try await LookoutPictureReading.picture(from: data)
        case .indexed(_, _, let fallback?): try await LookoutPictureReading.picture(at: fallback)
        case .indexed: throw QueryPicture.Failure.unreadable
        }
    }

    /// Searches with `request` and the current words, then publishes the results unless the search moved on.
    private func finish(_ request: LookoutSimilarRequest, token: UUID) async {
        var request = request
        request.words = await currentWords()
        guard isCurrent(token) else { return }
        let found: LookoutSimilarResults?
        do {
            found = try await reader.similar(request)
        } catch {
            LookoutLog.logger.error("Lookout picture search failed: \(String(describing: error), privacy: .public)")
            found = nil
        }
        guard isCurrent(token) else { return }
        results = found ?? LookoutSimilarResults(queryIsPicture: request.queryIsPicture)
        phase = found == nil ? .unavailable : .done
    }

    /// The current words with their vector and weight, embedding them when they're new; nil for no words. When the
    /// encoder fails they still count as keywords.
    private func currentWords() async -> LookoutSimilarWords? {
        let text = words
        guard !text.isEmpty else { return nil }
        if wordsVector?.text != text {
            do {
                let vector = try await encoder.embed(query: text)
                wordsVector = (text, vector)
            } catch {
                if !(error is CancellationError) {
                    LookoutLog.logger.error("Lookout can't read the words beside a picture: \(String(describing: error), privacy: .public)")
                }
            }
        }
        return LookoutSimilarWords(text: text, vector: wordsVector?.text == text ? wordsVector?.vector : nil,
                                   weight: wordsWeight)
    }

    private func fail(_ token: UUID) {
        guard isCurrent(token) else { return }
        results = LookoutSimilarResults(queryIsPicture: true)
        phase = .failed
    }

    private func isCurrent(_ token: UUID) -> Bool {
        !Task.isCancelled && generation == token
    }

    private func cancelRunning() {
        generation = UUID()
        pending?.cancel()
        pending = nil
    }

    isolated deinit {
        cancelRunning()
        warmTask?.cancel()
    }
}
