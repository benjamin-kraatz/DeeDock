import Foundation

/// How folders went into Vapor's orb. Never which folders.
nonisolated enum AnalyticsVaporSource: String, AnalyticsToken {
    /// Dropped on the orb or the open panel.
    case drop
    /// One Finder suggestion: a bubble, or Add in the panel's Found in section.
    case suggestion
    /// Add All on the suggestion capsule or in the panel.
    case addAll = "add_all"
}

/// The total size of one Vapor delete, in coarse buckets. Exact byte counts are not sent.
nonisolated enum AnalyticsVaporSizeBucket: String, AnalyticsToken {
    /// No folder had a measured size yet, or all were empty.
    case unknown
    case under100MB = "under_100mb"
    case under1GB = "under_1gb"
    case under10GB = "under_10gb"
    case over10GB = "over_10gb"

    init(bytes: Int64) {
        let megabyte: Int64 = 1_000_000
        switch bytes {
        case ...0: self = .unknown
        case ..<(100 * megabyte): self = .under100MB
        case ..<(1_000 * megabyte): self = .under1GB
        case ..<(10_000 * megabyte): self = .under10GB
        default: self = .over10GB
        }
    }
}

extension AnalyticsEvent {
    /// The analytics event for a Vapor usage event. `restore` additions are never reported.
    static func vapor(_ event: VaporAnalyticsEvent) -> AnalyticsEvent? {
        switch event {
        case .foldersAdded(let source, let count):
            let token: AnalyticsVaporSource
            switch source {
            case .drop: token = .drop
            case .suggestion: token = .suggestion
            case .addAll: token = .addAll
            case .restore: return nil
            }
            return .vaporFoldersAdded(source: token, count: count)
        case .deleted(let count, let bytes):
            return .vaporDeleted(count: count, size: AnalyticsVaporSizeBucket(bytes: bytes))
        case .undone(let count):
            return .vaporUndo(count: count)
        }
    }
}
