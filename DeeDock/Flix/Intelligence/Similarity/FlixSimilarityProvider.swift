import Foundation

/// More like this, and the cached answers Smart Filter `.about` and `.amountOver` rules read.
///
/// **More like this** ranks the history's items by how close their Lookout vectors are to the
/// item's own stored vector (`FlixSemanticScoring.ranked`), like with like (text or pictures). It
/// stays inside the history: Flix Files shows what you touched, not the whole index. Without
/// Lookout, or for an item Lookout hasn't read, it falls back to the same folder and kind, then the
/// same kind with a shared name word, newest first.
///
/// **Cached matches** answer synchronously while the list builds: `.about(topic)` from the topic
/// cache (Lookout's matches, kept by searches and by ``warmSmartFilters()``) or from captions and
/// names; `.amountOver` from the totals the analysis cache read. A topic never asked returns nil,
/// so the rule falls back to matching words.
@MainActor
final class FlixSimilarityProvider: FlixSimilarityProviding {
    static let limit = 12
    private let services: FlixSmartServices
    private var warmTask: Task<Void, Never>?

    init(services: FlixSmartServices) {
        self.services = services
    }

    func stop() {
        warmTask?.cancel()
        warmTask = nil
    }

    func similar(to item: FlixItem, in items: [FlixItem]) async -> [FlixItem.ID] {
        let others = items.filter { $0.id != item.id && $0.path != nil && $0.kind != .app }
        if let path = item.path {
            let vectors = await services.semantic.vectors(for: [path] + others.prefix(2_000).compactMap(\.path))
            guard !Task.isCancelled else { return [] }
            if let source = vectors[path] {
                let candidates = others.compactMap { other -> (id: FlixItem.ID, vector: [Float])? in
                    guard let vector = other.path.flatMap({ vectors[$0] }), vector.isPicture == source.isPicture else { return nil }
                    return (other.id, vector.vector)
                }
                let ranked = FlixSemanticScoring.ranked(source.vector, against: candidates, limit: Self.limit)
                if !ranked.isEmpty { return ranked.map(\.id) }
            }
        }
        return Self.fallback(for: item, in: others)
    }

    /// Same folder and kind first, then same kind with a shared distinctive name word.
    static func fallback(for item: FlixItem, in others: [FlixItem]) -> [FlixItem.ID] {
        let folder = item.path.map { ($0 as NSString).deletingLastPathComponent }
        let sameKind = { (other: FlixItem) in
            other.kind == item.kind || (Set([other.kind, item.kind]).isSubset(of: [.image, .screenshot]))
        }
        let words = FlixWords.distinctive(item.name)
        let sameFolder = others.filter { other in
            sameKind(other) && other.path.map { ($0 as NSString).deletingLastPathComponent } == folder
        }
        let sharedWord = others.filter { other in
            sameKind(other) && !words.isEmpty && !FlixWords.distinctive(other.name).isDisjoint(with: words)
        }
        var seen = Set<FlixItem.ID>()
        return (sharedWord + sameFolder).filter { seen.insert($0.id).inserted }.prefix(limit).map(\.id)
    }

    func cachedMatch(topic: String, item: FlixItem) -> Bool? {
        if let amount = FlixSmartFilterRule.amount(inTopic: topic) {
            guard let total = item.path.flatMap({ services.analyses[$0]?.total }) else { return false }
            return total > amount
        }
        let words = FlixWords.words(topic)
        let caption = item.path.flatMap { services.analyses[$0]?.caption } ?? ""
        if FlixWords.containsAll(words, in: item.name + " " + caption) { return true }
        guard let paths = services.topics.paths(for: topic) else { return nil }
        return item.path.map(paths.contains) ?? false
    }

    /// Asks Lookout about every `.about` topic of the saved Smart Filters, in the background, so
    /// their lists and counts can match by meaning. Called on each history pass; topics are asked
    /// again after ten minutes at most (`FlixTopicCache`).
    func warmSmartFilters() {
        guard services.settings.isEnabled, services.semantic.isAvailable, warmTask == nil else { return }
        let topics = services.smartFilters.flatMap(\.rules).compactMap { rule -> String? in
            if case .about(let topic) = rule { topic } else { nil }
        }
        guard !topics.isEmpty else { return }
        warmTask = Task { [weak self] in
            guard let self else { return }
            await services.topics.refresh(topics, index: services.semantic)
            warmTask = nil
        }
    }
}
