import Foundation

/// The persisted activity history and the merge rules every source goes through.
///
/// A plain value so the rules are testable without a store. Invariants after every mutation:
/// - one item per ``FlixItem/key`` (path or page);
/// - `items` sorted by `date`, newest first;
/// - at most ``capacity`` items, flagged items exempt; at most ``noiseCapacity`` noise items;
/// - an item removed from Flix Files comes back only with an event newer than its removal.
nonisolated struct FlixHistoryDocument: Codable, Equatable, Sendable {
    /// Total items kept. Older unflagged items fall off first.
    static let capacity = 5_000
    /// Noise items kept, so a build folder cannot push real activity out.
    static let noiseCapacity = 200
    static let currentVersion = 1

    var version = currentVersion
    var items: [FlixItem] = []
    /// Keys removed from Flix Files, with when. Pruned with the items they refer to.
    var removed: [String: Date] = [:]
    /// When the panel was last opened. Drives the tile's unseen badge.
    var lastSeen: Date = .distantPast

    init() {}

    private enum CodingKeys: String, CodingKey { case version, items, removed, lastSeen }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        items = try container.decodeIfPresent([FlixItem].self, forKey: .items) ?? []
        removed = try container.decodeIfPresent([String: Date].self, forKey: .removed) ?? [:]
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen) ?? .distantPast
        normalize()
    }

    /// Merges one observed event.
    ///
    /// A newer event updates the item's activity and date and moves it up; an older or equal one
    /// only fills in details that were missing. Identity, flag, and first-seen date are kept.
    /// - Returns: True when anything changed.
    @discardableResult
    mutating func record(_ event: FlixActivityEvent) -> Bool {
        let key = event.key
        if let removedAt = removed[key] {
            guard event.date > removedAt else { return false }
            removed[key] = nil
        }
        var changed = false
        if let path = event.path, FlixNoiseRules.completedPath(ofPartial: path) == nil {
            // A finished download replaces its partial entry (`Report.pdf.crdownload`).
            let partials = Set(FlixNoiseRules.partialDownloadExtensions.map { "file:" + path + "." + $0 })
            let before = items.count
            items.removeAll { partials.contains($0.key) }
            changed = items.count != before
        }
        if let index = items.firstIndex(where: { $0.key == key }) {
            var item = items[index]
            let original = item
            if event.date > item.date {
                item.activity = event.activity
                item.date = event.date
                if !event.name.isEmpty { item.name = event.name }
                item.kind = event.kind
            } else if event.date == item.date, event.activity != item.activity,
                      Self.precedence(event.activity) > Self.precedence(item.activity) {
                // Two sources saw the same moment: a download beats "new", "new" beats "saved".
                item.activity = event.activity
            }
            item.sourcePage = item.sourcePage ?? event.sourcePage
            item.contentTypeIdentifier = item.contentTypeIdentifier ?? event.contentTypeIdentifier
            item.byteSize = event.byteSize ?? item.byteSize
            item.bundleIdentifier = item.bundleIdentifier ?? event.bundleIdentifier
            if let link = event.link { item.link = link }
            guard item != original else { return changed }
            items.remove(at: index)
            insertSorted(item)
        } else {
            insertSorted(FlixItem(path: event.path, link: event.link, name: event.name, kind: event.kind,
                                  activity: event.activity, date: event.date, sourcePage: event.sourcePage,
                                  contentTypeIdentifier: event.contentTypeIdentifier, byteSize: event.byteSize,
                                  bundleIdentifier: event.bundleIdentifier))
        }
        enforceCapacity()
        return true
    }

    /// Removes items from Flix Files. The files stay where they are.
    mutating func remove(_ ids: Set<FlixItem.ID>, at date: Date = .now) {
        for item in items where ids.contains(item.id) { removed[item.key] = date }
        items.removeAll { ids.contains($0.id) }
    }

    /// Puts back items removed by ``remove(_:at:)``, for Undo.
    mutating func restore(_ restored: [FlixItem]) {
        for item in restored where !items.contains(where: { $0.key == item.key }) {
            removed[item.key] = nil
            insertSorted(item)
        }
        enforceCapacity()
    }

    /// Drops items whose files are gone, without remembering them as removed.
    mutating func forget(_ ids: Set<FlixItem.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    mutating func setFlagged(_ flagged: Bool, for ids: Set<FlixItem.ID>) {
        for index in items.indices where ids.contains(items[index].id) { items[index].isFlagged = flagged }
    }

    /// Points an item at its new place after Flix Files moved or renamed it, keeping its identity.
    mutating func relocate(_ id: FlixItem.ID, to path: String, name: String) {
        let path = FlixPaths.standardized(path)
        items.removeAll { $0.key == "file:" + path && $0.id != id }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].path = path
        items[index].name = name
    }

    /// Items that arrived by themselves since the panel was last opened, noise excluded.
    func unseenCount(hidingNoise: Bool = true) -> Int {
        items.lazy.filter { item in
            item.date > lastSeen && item.activity.countsAsNew && !(hidingNoise && FlixNoiseRules.isNoise(path: item.path))
        }.count
    }

    /// Restores the invariants after decoding or a bulk change.
    mutating func normalize() {
        var seen = Set<String>()
        items = items.sorted { $0.date > $1.date }.filter { seen.insert($0.key).inserted }
        enforceCapacity()
        let keys = Set(items.map(\.key))
        // A tombstone matters only while something could bring its key back; keep a month of them.
        let horizon = Date.now.addingTimeInterval(-60 * 86_400)
        removed = removed.filter { !keys.contains($0.key) && $0.value > horizon }
    }

    private mutating func insertSorted(_ item: FlixItem) {
        let index = items.firstIndex { $0.date < item.date } ?? items.endIndex
        items.insert(item, at: index)
    }

    private mutating func enforceCapacity() {
        var noise = 0
        var kept = 0
        items = items.filter { item in
            if item.isFlagged { return true }
            if FlixNoiseRules.isNoise(path: item.path) {
                noise += 1
                return noise <= Self.noiseCapacity
            }
            kept += 1
            return kept <= Self.capacity
        }
        while items.count > Self.capacity, let index = items.lastIndex(where: { !$0.isFlagged }) {
            items.remove(at: index)
        }
    }

    /// Which activity wins when two sources report the same instant.
    private static func precedence(_ activity: FlixActivity) -> Int {
        switch activity {
        case .kept: 6
        case .link: 5
        case .downloaded: 4
        case .created: 3
        case .saved: 2
        case .opened: 1
        }
    }
}
