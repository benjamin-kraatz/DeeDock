import Foundation

/// Optional typed details loaded after the directory listing, never from the pointer path.
nonisolated enum FolderStackMediaMetadata: Equatable, Sendable {
    case image(width: Int, height: Int)
    case pdf(pageCount: Int)
    case audio(duration: TimeInterval)
    case video(duration: TimeInterval)
}

/// Process-lifetime cache identity: listing path plus the modification date and size used to detect replacement.
nonisolated struct FolderStackMediaCacheKey: Hashable, Sendable {
    let identity: String
    let modifiedAt: Date?
    let byteCount: Int64?

    init(_ reference: FolderStackEntryReference) {
        identity = reference.id
        modifiedAt = reference.modifiedAt
        byteCount = reference.byteCount
    }
}

/// Distinguishes a loaded value from a remembered miss so corrupt local files are not parsed again.
nonisolated enum FolderStackMediaCacheValue: Equatable, Sendable {
    case metadata(FolderStackMediaMetadata)
    case unavailable
}

/// Shared store for folder-stack media headers and remembered misses.
///
/// The cache keeps at most ``capacity`` entries. A long session stores one entry per image, PDF, or audio file, including failed reads (`.unavailable`). Without a cap the dictionary grows for the life of the process.
/// 1024 covers a large folder plus stacks visited recently. Each value is a few integers, so this limit is higher than the 256-entry folder-metrics cache.
/// Eviction drops the oldest insertion. Storing a key that is already present replaces its value and leaves the order list unchanged.
actor FolderStackMediaCache {
    static let shared = FolderStackMediaCache()

    /// Maximum retained headers and remembered misses, in insertion order.
    nonisolated static let capacity = 1024

    private var values: [FolderStackMediaCacheKey: FolderStackMediaCacheValue] = [:]
    private var insertionOrder: [FolderStackMediaCacheKey] = []

    func value(for key: FolderStackMediaCacheKey) -> FolderStackMediaCacheValue? {
        values[key]
    }

    func store(_ value: FolderStackMediaCacheValue, for key: FolderStackMediaCacheKey) {
        // Updating a stored key must not append. A second slot would make eviction drop a live entry early.
        if values[key] == nil {
            insertionOrder.append(key)
        }
        values[key] = value
        evictIfNeeded()
    }

    /// Insertion-order slots. Equals the number of retained keys when each key occupies one slot.
    var insertionCount: Int { insertionOrder.count }

    private func evictIfNeeded() {
        while values.count > Self.capacity, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}
