import Foundation

/// The persisted activity history and the merge rules every source goes through.
///
/// A plain value so the rules are testable without a store. Invariants after every mutation:
/// - one item per ``FlixItem/key`` (path or page);
/// - `items` sorted by `date`, newest first, then by key (``precedes(_:_:)``);
/// - at most ``capacity`` items in all, never dropping a flagged one; at most ``noiseCapacity``
///   unflagged noise items;
/// - an item removed from Flix Files comes back only with an event newer than its removal;
/// - after Clear History, no event dated at or before the clear is recorded (``clearedAt``);
/// - a file row's download page is set only by ``attachVerifiedSource(_:toPath:)``, never from an
///   event, so a stored page is always one the link tracker verified.
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
    /// When the history was last cleared. Sources replay the past (Spotlight seeds the last 30
    /// days of opened files at every launch), so an event dated at or before this is dropped;
    /// otherwise cleared items would come back. Survives ``cleared(at:)``, unlike the tombstones.
    var clearedAt: Date?

    init() {}

    /// An empty history that remembers it was cleared at `date`.
    static func cleared(at date: Date) -> FlixHistoryDocument {
        var document = FlixHistoryDocument()
        document.lastSeen = date
        document.clearedAt = date
        return document
    }

    private enum CodingKeys: String, CodingKey { case version, items, removed, lastSeen, clearedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        items = try container.decodeIfPresent([FlixItem].self, forKey: .items) ?? []
        removed = try container.decodeIfPresent([String: Date].self, forKey: .removed) ?? [:]
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen) ?? .distantPast
        clearedAt = try container.decodeIfPresent(Date.self, forKey: .clearedAt)
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
        guard admits(event) else { return false }
        var changed = false
        for partial in Self.partialKeys(replacedBy: event) {
            // A finished download replaces its partial entry (`Report.pdf.crdownload`).
            if let index = items.firstIndex(where: { $0.key == partial }) {
                items.remove(at: index)
                changed = true
            }
        }
        let added: FlixItem?
        if let index = items.firstIndex(where: { $0.key == key }) {
            let item = Self.merged(items[index], with: event)
            guard item != items[index] else { return changed }
            items.remove(at: index)
            insertSorted(item)
            added = nil
        } else {
            let item = Self.newItem(from: event)
            insertSorted(item)
            added = item
        }
        // The caps held before this event, and a merge keeps the item's path and flag, so only a new
        // item can break one: a noise item the noise cap, any item the total. Checking only then
        // keeps a single event from running the noise rules over the whole history.
        if let added, items.count > Self.capacity || FlixNoiseRules.isNoise(path: added.path) {
            enforceCapacity()
        }
        return true
    }

    /// Merges a batch of events with the same rules as calling ``record(_:)`` for each in order,
    /// but sorts and enforces the capacity once, so a Spotlight gather or a folder watcher batch of
    /// hundreds of events costs one pass over the history instead of one per event.
    ///
    /// The clear cutoff, tombstones, partial downloads, flags, and the noise cap behave exactly as
    /// in sequential merging. The one difference is at the capacity edge: sequential merging may
    /// drop an old item mid-batch and re-create it (with a new identifier) when a later event in
    /// the same batch names it again; the batch keeps it.
    /// - Returns: True when anything changed.
    @discardableResult
    mutating func record(batch events: [FlixActivityEvent]) -> Bool {
        guard events.count > 1 else { return events.first.map { record($0) } ?? false }
        var byKey = [String: FlixItem](minimumCapacity: items.count + events.count)
        for item in items where byKey[item.key] == nil { byKey[item.key] = item }
        var changed = false
        for event in events {
            guard admits(event) else { continue }
            for partial in Self.partialKeys(replacedBy: event) where byKey.removeValue(forKey: partial) != nil {
                changed = true
            }
            if let item = byKey[event.key] {
                let merged = Self.merged(item, with: event)
                if merged != item {
                    byKey[event.key] = merged
                    changed = true
                }
            } else {
                byKey[event.key] = Self.newItem(from: event)
                changed = true
            }
        }
        guard changed else { return false }
        items = byKey.values.sorted(by: Self.precedes)
        enforceCapacity()
        return true
    }

    /// Whether the clear cutoff and the tombstones let `event` in. Clears the tombstone of a key
    /// whose event is newer than its removal.
    private mutating func admits(_ event: FlixActivityEvent) -> Bool {
        if let clearedAt, event.date <= clearedAt { return false }
        if let removedAt = removed[event.key] {
            guard event.date > removedAt else { return false }
            removed[event.key] = nil
        }
        return true
    }

    /// The keys of the partial downloads a finished file replaces; empty for a partial file itself.
    private static func partialKeys(replacedBy event: FlixActivityEvent) -> [String] {
        guard let path = event.path, FlixNoiseRules.completedPath(ofPartial: path) == nil else { return [] }
        return FlixNoiseRules.partialDownloadExtensions.map { "file:" + path + "." + $0 }
    }

    /// `item` with `event` merged in. See ``record(_:)``.
    ///
    /// A newer event takes over the file identity it carries, or clears it when it carries none,
    /// so the background pass captures the file as it is now: a newer event means the file may
    /// have changed. An older event only fills a missing identity. A download page is never taken
    /// from an event (``FlixItem/sourcePageIsVerified``); only its host is.
    private static func merged(_ original: FlixItem, with event: FlixActivityEvent) -> FlixItem {
        var item = original
        if event.date > item.date {
            item.activity = event.activity
            item.date = event.date
            if !event.name.isEmpty { item.name = event.name }
            item.kind = event.kind
            if event.path != nil { item.fileIdentity = event.fileIdentity }
        } else {
            if event.date == item.date, event.activity != item.activity,
               precedence(event.activity) > precedence(item.activity) {
                // Two sources saw the same moment: a download beats "new", "new" beats "saved".
                item.activity = event.activity
            }
            item.fileIdentity = item.fileIdentity ?? event.fileIdentity
        }
        item.sourceHost = item.sourceHost ?? event.sourceHost
        item.contentTypeIdentifier = item.contentTypeIdentifier ?? event.contentTypeIdentifier
        item.byteSize = event.byteSize ?? item.byteSize
        item.bundleIdentifier = item.bundleIdentifier ?? event.bundleIdentifier
        if let link = event.link { item.link = link }
        return item
    }

    private static func newItem(from event: FlixActivityEvent) -> FlixItem {
        FlixItem(path: event.path, link: event.link, name: event.name, kind: event.kind, activity: event.activity,
                 date: event.date, sourceHost: event.sourceHost, contentTypeIdentifier: event.contentTypeIdentifier,
                 byteSize: event.byteSize, bundleIdentifier: event.bundleIdentifier, fileIdentity: event.fileIdentity)
    }

    /// The list's order: newest first, and by key among items of the same moment, so sequential
    /// and batch merging produce the same list.
    static func precedes(_ a: FlixItem, _ b: FlixItem) -> Bool {
        a.date != b.date ? a.date > b.date : a.key < b.key
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

    /// Points an item at its new place after Flix Files moved or renamed it, keeping its row.
    /// - Parameter identity: The moved file as it is now, so the next command recognizes it.
    mutating func relocate(_ id: FlixItem.ID, to path: String, name: String, identity: FlixFileIdentity?) {
        let path = FlixPaths.standardized(path)
        items.removeAll { $0.key == "file:" + path && $0.id != id }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].path = path
        items[index].name = name
        items[index].fileIdentity = identity
    }

    /// Stores the identity of the file at an item's path, captured in the background or after a
    /// command found the file changed. Ignored when the item has moved on since (`path` differs).
    /// - Returns: True when the item changed.
    @discardableResult
    mutating func setIdentity(_ identity: FlixFileIdentity?, for id: FlixItem.ID, path: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].path == path,
              items[index].fileIdentity != identity else { return false }
        items[index].fileIdentity = identity
        return true
    }

    /// Stores the page a download came from on the file's row, after the link tracker verified the
    /// download arrived from a normal browser window showing that page. The only way a full page
    /// address reaches a file row.
    /// - Returns: True when the item changed.
    @discardableResult
    mutating func attachVerifiedSource(_ page: URL, toPath path: String) -> Bool {
        let path = FlixPaths.standardized(path)
        guard let index = items.firstIndex(where: { $0.path == path }),
              items[index].sourcePage != page || items[index].sourcePageIsVerified != true else { return false }
        items[index].sourcePage = page
        items[index].sourcePageIsVerified = true
        items[index].sourceHost = FlixPaths.displayHost(of: page) ?? items[index].sourceHost
        return true
    }

    /// Strips download pages the settings no longer allow (``FlixSourcePolicy``).
    /// - Returns: True when any item changed.
    @discardableResult
    mutating func applySourcePolicy(_ settings: FlixSettings) -> Bool {
        var changed = false
        for index in items.indices {
            let allowed = FlixSourcePolicy.apply(to: items[index], settings: settings)
            if allowed != items[index] {
                items[index] = allowed
                changed = true
            }
        }
        return changed
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
        items = items.sorted(by: Self.precedes).filter { seen.insert($0.key).inserted }
        enforceCapacity()
        let keys = Set(items.map(\.key))
        // A tombstone matters only while something could bring its key back; keep a month of them.
        let horizon = Date.now.addingTimeInterval(-60 * 86_400)
        removed = removed.filter { !keys.contains($0.key) && $0.value > horizon }
    }

    private mutating func insertSorted(_ item: FlixItem) {
        let index = items.firstIndex { Self.precedes(item, $0) } ?? items.endIndex
        items.insert(item, at: index)
    }

    /// Keeps at most ``capacity`` items in all and ``noiseCapacity`` unflagged noise items, dropping
    /// the oldest unflagged ones. Flagged items are always kept and take their place in the total.
    /// One pass, newest first.
    private mutating func enforceCapacity() {
        let flagged = items.count(where: \.isFlagged)
        let unflaggedRoom = max(0, Self.capacity - flagged)
        var noise = 0
        var unflagged = 0
        items = items.filter { item in
            if item.isFlagged { return true }
            if FlixNoiseRules.isNoise(path: item.path) {
                noise += 1
                guard noise <= Self.noiseCapacity else { return false }
            }
            unflagged += 1
            return unflagged <= unflaggedRoom
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
