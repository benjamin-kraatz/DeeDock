import Foundation
import Observation

/// What Lookout found for each "about" topic Flix Files asked it: the paths it matched by meaning or
/// words. Smart Filter `.about` rules and searches read it synchronously, for every item on every
/// list build, so it must be filled in the background first.
///
/// `@Observable`, so a list built before a topic arrived rebuilds once it does. Entries are asked
/// again after ten minutes; at most 64 topics are kept, the oldest dropped first. Main actor.
@MainActor @Observable
final class FlixTopicCache {
    private(set) var topics: [String: Set<String>] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    private static let lifetime: TimeInterval = 600
    private static let limit = 64

    /// The cache key for a topic: folded case and diacritics, single spaces.
    nonisolated static func key(_ topic: String) -> String {
        FlixWords.words(topic).joined(separator: " ")
    }

    /// The paths Lookout matched for `topic`, or nil when it was never asked.
    func paths(for topic: String) -> Set<String>? { topics[Self.key(topic)] }

    /// Asks Lookout about each topic that is missing or stale. Does nothing without Lookout.
    func refresh(_ wanted: [String], index: FlixSemanticIndex, now: Date = .now) async {
        guard index.isAvailable else { return }
        for topic in wanted {
            let key = Self.key(topic)
            guard !key.isEmpty, !inFlight.contains(key),
                  fetchedAt[key].map({ now.timeIntervalSince($0) > Self.lifetime }) ?? true else { continue }
            inFlight.insert(key)
            let matches = await index.contentMatches(topic)
            inFlight.remove(key)
            guard !Task.isCancelled else { return }
            if let matches { store(key, paths: Set(matches.keys), now: now) }
        }
    }

    /// Records Lookout's matches for a topic a search already asked about.
    func store(topic: String, paths: Set<String>, now: Date = .now) {
        store(Self.key(topic), paths: paths, now: now)
    }

    private func store(_ key: String, paths: Set<String>, now: Date) {
        if topics.count >= Self.limit, topics[key] == nil, let oldest = fetchedAt.min(by: { $0.value < $1.value })?.key {
            topics[oldest] = nil
            fetchedAt[oldest] = nil
        }
        if topics[key] != paths { topics[key] = paths }
        fetchedAt[key] = now
    }
}
