import Foundation

/// Groups recent activity into work threads: items tied by meaning, by shared name words, or by a
/// shared working folder, close enough in time.
///
/// Two items are linked when, within ``linkWindow`` of each other, Lookout says they are about the
/// same thing (`FlixSemanticScoring.areRelated`), or their names share a distinctive word
/// ("Oak", "Berlin"), or within ``folderWindow`` they sit in the same working folder. Downloads, the
/// Desktop, Documents, and other catch-all folders never link by folder alone. Linked items form a
/// thread (connected components); a thread needs ``minimumMembers``. Without Lookout the same rules
/// run without the meaning link, which is the time-and-folder fallback.
///
/// Pure and `nonisolated`: the provider runs it off the main actor (`cluster(_:)` is
/// `@concurrent`). At most ``entryLimit`` entries are compared, pairwise.
nonisolated enum FlixThreadClusterer {
    struct Entry: Sendable {
        var id: FlixItem.ID
        var date: Date
        /// The working folder: a file's parent, or a folder item's own path.
        var folder: String?
        var words: Set<String>
        var vector: LookoutFileVector?
    }

    static let linkWindow: TimeInterval = 72 * 3_600
    static let folderWindow: TimeInterval = 12 * 3_600
    static let minimumMembers = 3
    static let entryLimit = 300
    static let threadLimit = 8
    static let memberLimit = 40

    /// Folders that hold everything and say nothing about a thread.
    static func catchAllFolders(home: String = NSHomeDirectory()) -> Set<String> {
        let names = ["", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
                     "Library/Mobile Documents/com~apple~CloudDocs"]
        return Set(names.map { FlixPaths.standardized(home + "/" + $0) })
    }

    @concurrent static func cluster(_ entries: [Entry], catchAll: Set<String>) async -> [[FlixItem.ID]] {
        groups(entries, catchAll: catchAll)
    }

    /// The threads among `entries`, each newest member first, newest thread first.
    static func groups(_ entries: [Entry], catchAll: Set<String>) -> [[FlixItem.ID]] {
        let entries = Array(entries.sorted { $0.date > $1.date }.prefix(entryLimit))
        var parent = Array(entries.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        for a in entries.indices {
            for b in entries.indices where b > a {
                let gap = abs(entries[a].date.timeIntervalSince(entries[b].date))
                guard gap <= linkWindow, linked(entries[a], entries[b], gap: gap, catchAll: catchAll) else { continue }
                parent[root(a)] = root(b)
            }
        }
        var components: [Int: [Int]] = [:]
        for index in entries.indices { components[root(index), default: []].append(index) }
        return components.values
            .filter { $0.count >= minimumMembers }
            .map { members in members.sorted { entries[$0].date > entries[$1].date } }
            .sorted { entries[$0[0]].date > entries[$1[0]].date }
            .prefix(threadLimit)
            .map { members in members.prefix(memberLimit).map { entries[$0].id } }
    }

    static func linked(_ a: Entry, _ b: Entry, gap: TimeInterval, catchAll: Set<String>) -> Bool {
        if let va = a.vector, let vb = b.vector, FlixSemanticScoring.areRelated(va, vb) { return true }
        if !a.words.isDisjoint(with: b.words) { return true }
        if gap <= folderWindow, let folder = a.folder, folder == b.folder, !catchAll.contains(folder) { return true }
        return false
    }
}
