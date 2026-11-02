import Foundation

/// One tick of one app's in-memory history.
nonisolated struct AppHealthHistoryEntry: Sendable, Equatable {
    let sample: AppHealthSample
    /// Whether a `sample` row for this tick is on disk, so a backfill writes each tick at most once.
    var written: Bool
}

/// The last ten minutes of computed samples per app, written or not.
///
/// Labelling reads it to evaluate its rules, and a label backfills its window from it, so every labelled window is
/// complete on disk even when the write policy skipped quiet ticks. Each app keeps at most `capacity` entries,
/// oldest first. Nothing here is persisted.
nonisolated struct AppHealthHistory: Sendable {
    /// 30 ticks of 20 s: ten minutes.
    static let capacity = 30

    private(set) var entries: [String: [AppHealthHistoryEntry]] = [:]

    /// Apps with at least one entry.
    var apps: [String] { Array(entries.keys) }

    func entries(for app: String) -> [AppHealthHistoryEntry] {
        entries[app] ?? []
    }

    mutating func append(_ sample: AppHealthSample, written: Bool) {
        var list = entries[sample.app] ?? []
        list.append(AppHealthHistoryEntry(sample: sample, written: written))
        if list.count > Self.capacity { list.removeFirst(list.count - Self.capacity) }
        entries[sample.app] = list
    }

    /// Marks unwritten entries of `app` inside `from…to` as written and returns their samples, oldest first.
    mutating func takeUnwritten(app: String, from: Date, to: Date) -> [AppHealthSample] {
        guard var list = entries[app] else { return [] }
        var taken: [AppHealthSample] = []
        for index in list.indices where !list[index].written
            && list[index].sample.timestamp >= from && list[index].sample.timestamp <= to {
            list[index].written = true
            taken.append(list[index].sample)
        }
        entries[app] = list
        return taken
    }

    /// Drops an app's entries up to and including `date`, after its termination event. Later entries belong to a
    /// new instance that launched in the meantime and stay.
    mutating func removeEntries(for app: String, through date: Date) {
        guard let list = entries[app] else { return }
        let remaining = list.filter { $0.sample.timestamp > date }
        entries[app] = remaining.isEmpty ? nil : remaining
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
