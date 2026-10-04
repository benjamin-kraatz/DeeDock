import Foundation

/// Exact counts of high-frequency interactions since the last summary, kept across launches.
///
/// Incrementing only touches memory. `persist()` writes the totals; ``Analytics`` calls it on a
/// coarse timer and at quit, so a pointer path never encodes or writes anything.
@MainActor
final class AnalyticsCounterStore {
    private struct Document: Codable {
        var since: Date
        var counts: [String: Int]
    }

    private let defaults: UserDefaults?
    private let key = "analytics.counters.v1"
    private var document: Document
    private var isDirty = false

    /// A nil `defaults` keeps the counts in memory only, for previews and tests.
    init(defaults: UserDefaults?, now: Date = Date()) {
        self.defaults = defaults
        document = defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(Document.self, from: $0) }
            ?? Document(since: now, counts: [:])
    }

    /// When the current counting period began.
    var since: Date { document.since }
    var isEmpty: Bool { document.counts.isEmpty }

    func increment(_ counter: AnalyticsCounter, by amount: Int = 1) {
        document.counts[counter.key, default: 0] += amount
        isDirty = true
    }

    /// Writes the counts if they changed since the last write.
    func persist() {
        guard isDirty, let data = try? JSONEncoder().encode(document) else { return }
        defaults?.set(data, forKey: key)
        isDirty = false
    }

    /// Returns the counts as summary properties and starts a new period.
    func drain(now: Date = Date()) -> AnalyticsProperties {
        var properties: AnalyticsProperties = ["period_seconds": AnalyticsValue(now.timeIntervalSince(document.since).rounded())]
        properties.merge(AnalyticsProperties(counterTotals: document.counts))
        document = Document(since: now, counts: [:])
        isDirty = true
        persist()
        return properties
    }

    /// Forgets every count without reporting it.
    func discard(now: Date = Date()) {
        document = Document(since: now, counts: [:])
        defaults?.removeObject(forKey: key)
        isDirty = false
    }
}
