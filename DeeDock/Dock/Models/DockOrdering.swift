import Foundation

/// The ordering policy is independent of workspace enumeration order and process IDs.
enum DockOrdering {
    /// Keeps the first reference for each stable app identity, preserving input order.
    static func unique(_ references: [ApplicationReference]) -> [ApplicationReference] {
        var seen = Set<String>()
        return references.filter { seen.insert($0.id).inserted }
    }

    /// Retains surviving apps in their previous order and appends new identities by display name.
    /// An empty previous order therefore produces a sorted initial snapshot.
    static func runningOrder(previous: [String], current: [ApplicationReference]) -> [String] {
        let uniqueApps = unique(current)
        let currentIDs = Set(uniqueApps.map(\.id))
        let retained = previous.filter { currentIDs.contains($0) }
        let retainedIDs = Set(retained)
        let added = uniqueApps.filter { !retainedIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return retained + added.map(\.id)
    }

    /// Places pinned apps first and appends running-only identities without duplicates.
    static func itemOrder(favorites: [ApplicationReference], runningIDs: [String]) -> [String] {
        let pinned = unique(favorites).map(\.id)
        let pinnedIDs = Set(pinned)
        var seen = pinnedIDs
        return pinned + runningIDs.filter { !pinnedIDs.contains($0) && seen.insert($0).inserted }
    }
}
