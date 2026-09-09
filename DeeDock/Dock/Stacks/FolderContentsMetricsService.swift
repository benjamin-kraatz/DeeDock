import Foundation

/// Process-lifetime cache of finished folder totals, keyed by path and the folder's modification date.
///
/// A later listing with a different `modifiedAt` misses and is measured again. Calculating values are never stored.
actor FolderContentsMetricsCache {
    nonisolated static let shared = FolderContentsMetricsCache()

    private struct Record: Sendable {
        let modifiedAt: Date?
        let metrics: FolderContentsMetrics
    }

    private var records: [String: Record] = [:]
    private var insertionOrder: [String] = []
    private let limit = 256

    func finalMetrics(for url: URL, modifiedAt: Date?) -> FolderContentsMetrics? {
        let key = url.standardizedFileURL.path
        guard let record = records[key], record.metrics.isFinal, record.modifiedAt == modifiedAt else {
            return nil
        }
        return record.metrics
    }

    func hits(for folders: [(url: URL, modifiedAt: Date?)]) -> [String: FolderContentsMetrics] {
        var result: [String: FolderContentsMetrics] = [:]
        for folder in folders {
            let key = folder.url.standardizedFileURL.path
            if let metrics = finalMetrics(for: folder.url, modifiedAt: folder.modifiedAt) {
                result[key] = metrics
            }
        }
        return result
    }

    func store(_ metrics: FolderContentsMetrics, for url: URL, modifiedAt: Date?) {
        guard metrics.isFinal else { return }
        let key = url.standardizedFileURL.path
        if records[key] == nil {
            insertionOrder.append(key)
        }
        records[key] = Record(modifiedAt: modifiedAt, metrics: metrics)
        evictIfNeeded()
    }

    func remove(at url: URL) {
        let key = url.standardizedFileURL.path
        records.removeValue(forKey: key)
        insertionOrder.removeAll { $0 == key }
    }

    private func evictIfNeeded() {
        while records.count > limit, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }
}

/// Measures sibling folders off the caller, two at a time, and publishes calculating then finished values.
nonisolated enum FolderContentsMetricsScheduler {
    static let concurrencyLimit = 2

    /// Walks each folder and calls `onUpdate` for calculating and finished snapshots.
    ///
    /// Cache hits skip the walk and publish the stored total once. Cancellation stops remaining walks.
    static func measure(
        _ folders: [FolderStackEntryReference],
        onUpdate: @Sendable (URL, FolderContentsMetrics) async -> Void
    ) async {
        guard !folders.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            let initial = min(concurrencyLimit, folders.count)
            while nextIndex < initial {
                let folder = folders[nextIndex]
                group.addTask { await measureOne(folder, onUpdate: onUpdate) }
                nextIndex += 1
            }
            for await _ in group {
                if nextIndex < folders.count {
                    let folder = folders[nextIndex]
                    group.addTask { await measureOne(folder, onUpdate: onUpdate) }
                    nextIndex += 1
                }
            }
        }
    }

    private static func measureOne(
        _ folder: FolderStackEntryReference,
        onUpdate: @Sendable (URL, FolderContentsMetrics) async -> Void
    ) async {
        if let cached = await FolderContentsMetricsCache.shared.finalMetrics(
            for: folder.url, modifiedAt: folder.modifiedAt
        ) {
            await onUpdate(folder.url, cached)
            return
        }

        do {
            try Task.checkCancellation()
            let children = try FolderContentsEnumerator.listVisibleChildren(folder.url)
            await onUpdate(folder.url, .calculating(immediateItemCount: children.count))
            let metrics = try FolderContentsEnumerator.measure(url: folder.url, children: children)
            await FolderContentsMetricsCache.shared.store(metrics, for: folder.url, modifiedAt: folder.modifiedAt)
            await onUpdate(folder.url, metrics)
        } catch is CancellationError {
            return
        } catch {
            await onUpdate(folder.url, FolderContentsMetrics(completeness: .incomplete))
        }
    }
}
