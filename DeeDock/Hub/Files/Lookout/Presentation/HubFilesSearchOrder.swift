import Foundation

/// One selectable search result, across both sections. The same file can be in both (its name and its contents
/// matched), so a name row and a Lookout row are different results.
nonisolated enum HubFilesSearchResultID: Hashable, Sendable {
    /// A Spotlight name result.
    case name(URL)
    /// A Lookout hit, by the path the index stores (`LookoutHit.id`).
    case lookout(String)
}

/// The order Up and Down walk through search results: the names, then Lookout's strong hits, then its weaker hits
/// while the "Weaker matches" fold is open. Pure, so the order and the steps are testable.
nonisolated enum HubFilesSearchOrder {
    /// Every selectable result in display order.
    static func flattened(names: [URL], lookout: LookoutResultSet, weakExpanded: Bool) -> [HubFilesSearchResultID] {
        names.map(HubFilesSearchResultID.name)
            + lookout.strong.map { .lookout($0.path) }
            + (weakExpanded ? lookout.weak.map { .lookout($0.path) } : [])
    }

    /// The result `delta` steps from `current`, clamped to the ends. Without a current result (or with one that is
    /// no longer listed), a forward step starts at the first result and a backward step at the last, as
    /// `HubFilesSelection.move` does. Nil when there are no results.
    static func step(from current: HubFilesSearchResultID?, by delta: Int,
                     in order: [HubFilesSearchResultID]) -> HubFilesSearchResultID? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            return delta >= 0 ? order.first : order.last
        }
        return order[min(max(index + delta, 0), order.count - 1)]
    }
}
