import Foundation

/// Turns Spotlight results into `HubFileItem`s for search and Recents.
nonisolated enum HubMetadataResults {
    /// The path and last-used date Spotlight reports for one result.
    struct Hit: Sendable {
        let path: String
        let lastUsed: Date?
    }

    /// Reads up to `limit` hits from a gathered query. Main actor (the query delivers there);
    /// cheap, it only reads attributes Spotlight already returned.
    @MainActor
    static func hits(from query: NSMetadataQuery, limit: Int) -> [Hit] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let count = min(query.resultCount, limit)
        var hits: [Hit] = []
        hits.reserveCapacity(count)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            hits.append(Hit(path: path,
                            lastUsed: item.value(forAttribute: "kMDItemLastUsedDate") as? Date))
        }
        return hits
    }

    /// Reads file-system details for each hit off the main actor and drops hidden items and items
    /// that vanished since Spotlight indexed them.
    static func items(for hits: [Hit]) async -> [(item: HubFileItem, lastUsed: Date?)] {
        await VolumeReads.run(qos: .userInitiated) {
            hits.compactMap { hit -> (item: HubFileItem, lastUsed: Date?)? in
                guard !hit.path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                      let item = HubDirectoryLister.item(at: URL(fileURLWithPath: hit.path)),
                      !item.isHidden else { return nil }
                return (item, hit.lastUsed)
            }
        }
    }
}
