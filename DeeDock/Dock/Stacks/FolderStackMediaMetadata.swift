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

/// Shared, cancellable store for folder-stack media headers.
actor FolderStackMediaCache {
    static let shared = FolderStackMediaCache()

    private var values: [FolderStackMediaCacheKey: FolderStackMediaCacheValue] = [:]

    func value(for key: FolderStackMediaCacheKey) -> FolderStackMediaCacheValue? {
        values[key]
    }

    func store(_ value: FolderStackMediaCacheValue, for key: FolderStackMediaCacheKey) {
        values[key] = value
    }
}
