import Foundation
import Observation
import os

/// Lookout's search with a picture: a dropped or pasted picture, or Find Similar on a file in the index.
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

    /// Whether Lookout is set up and on. Turning it off cancels the search and clears the results.
    var isAvailable = false {
        didSet {
            guard isAvailable != oldValue else { return }
            if !isAvailable, phase != .idle {
                cancelRunning()
                results = LookoutSimilarResults(queryIsPicture: results.queryIsPicture)
                phase = .unavailable
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
    /// The current search's vector and what it excludes, for `rescope`.
    @ObservationIgnored private var current: (vector: [Float], isPicture: Bool, excluding: Set<String>)?

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
    /// - Returns: Whether the search waits for the picture reader to load (it was cold).
    @discardableResult
    func search(_ input: LookoutPictureInput, source: AnalyticsLookoutImageSource,
                scope: HubFileSearch.Scope) -> Bool {
        cancelRunning()
        current = nil
        readSeconds = nil
        storedSource = nil
        results = LookoutSimilarResults(queryIsPicture: true)
        guard isAvailable else {
            phase = .unavailable
            return false
        }
        let token = generation
        let folder = scope.lookoutFolder
        let cold: Bool
        if case .indexed = input {
            cold = false
            phase = .lookingUp
        } else {
            cold = isReaderCold
            phase = cold ? .waking : .reading
            Analytics.track(LookoutAnalytics.imageSearch(source: source, cold: cold))
        }
        pending = Task { [weak self] in
            await self?.run(input, source: source, folder: folder, token: token)
        }
        return cold
    }

    /// Searches the current picture again within a new scope, with the vector it already has.
    ///
    /// - Returns: False when there's no vector yet (the picture was still being read): search again instead.
    @discardableResult
    func rescope(_ scope: HubFileSearch.Scope) -> Bool {
        guard let current, isAvailable else { return false }
        cancelRunning()
        let token = generation
        let request = LookoutSimilarRequest(vector: current.vector, queryIsPicture: current.isPicture,
                                            excluding: current.excluding, scope: scope.lookoutFolder, filter: filter)
        pending = Task { [weak self] in await self?.finish(request, token: token) }
        return true
    }

    /// Ends the search: cancels its work and forgets its vector and results.
    func clear() {
        cancelRunning()
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

    private func run(_ input: LookoutPictureInput, source: AnalyticsLookoutImageSource, folder: String?,
                     token: UUID) async {
        let excluding = Set([input.excludedPath].compactMap { $0 })
        var toRead = input
        if case .indexed(let path, let segmentID, let fallback) = input {
            if let stored = await reader.similarSource(path: path, segmentID: segmentID) {
                guard isCurrent(token) else { return }
                // A stored vector reads nothing, so it never waits for the picture reader.
                Analytics.track(LookoutAnalytics.imageSearch(source: source, cold: false))
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
            Analytics.track(LookoutAnalytics.imageSearch(source: source, cold: cold))
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

    private func finish(_ request: LookoutSimilarRequest, token: UUID) async {
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
