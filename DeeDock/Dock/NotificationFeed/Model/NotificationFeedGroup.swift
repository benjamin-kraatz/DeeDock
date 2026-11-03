import Foundation

/// The entries one sender posted, newest first, as the feed shows them together.
///
/// Senders are matched by the display name the banner showed, exactly as macOS spelled it.
/// System alerts, which name no app, form one group of their own.
nonisolated struct NotificationFeedGroup: Identifiable, Equatable, Sendable {
    /// Stable across arrivals and removals for as long as the sender has entries.
    let id: String
    /// The sender's display name, or nil for system alerts.
    let appName: String?
    /// Newest first. Never empty.
    let entries: [NotificationFeedEntry]

    /// The newest entry, drawn in front of a collapsed stack.
    var front: NotificationFeedEntry { entries[0] }
    /// A group of one is drawn as a plain row, never as a stack.
    var isStack: Bool { entries.count > 1 }

    /// The group identifier an entry belongs to.
    static func id(for entry: NotificationFeedEntry) -> String {
        entry.appName.map { "app:" + $0 } ?? "system"
    }
}

/// One selectable item in the feed's keyboard and VoiceOver order.
///
/// A collapsed stack is a single item, identified by its front entry. An unfolded group
/// contributes one item per entry.
nonisolated struct NotificationFeedItem: Identifiable, Equatable, Sendable {
    /// The entry this item shows: a plain row's entry, or the front entry of a stack.
    let entry: NotificationFeedEntry
    let group: NotificationFeedGroup
    /// True for a stack that is folded; acting on it acts on the whole group.
    let isCollapsedStack: Bool

    var id: NotificationFeedEntry.ID { entry.id }
    /// True for a row inside an unfolded group, which ← folds back.
    var isInExpandedGroup: Bool { group.isStack && !isCollapsedStack }
}

/// Groups the feed's entries by sender. Pure, so ordering and folding can be tested directly.
nonisolated enum NotificationFeedGrouping {
    /// The most cards a folded stack draws: the front entry and two peeking behind it.
    static let maximumStackDepth = 3

    /// Groups `entries` (newest first) by sender.
    ///
    /// A group sits where its newest entry would, so the sender that posted last is at the top.
    /// Entries keep their order inside a group.
    static func groups(_ entries: [NotificationFeedEntry]) -> [NotificationFeedGroup] {
        var order: [String] = []
        var members: [String: [NotificationFeedEntry]] = [:]
        var names: [String: String?] = [:]
        for entry in entries {
            let id = NotificationFeedGroup.id(for: entry)
            if members[id] == nil {
                order.append(id)
                names[id] = entry.appName
            }
            members[id, default: []].append(entry)
        }
        return order.map { id in
            NotificationFeedGroup(id: id, appName: names[id] ?? nil, entries: members[id] ?? [])
        }
    }

    /// The selectable items in display order.
    /// - Parameter expanded: Identifiers of the groups the person unfolded.
    static func items(_ groups: [NotificationFeedGroup], expanded: Set<String>) -> [NotificationFeedItem] {
        groups.flatMap { group -> [NotificationFeedItem] in
            if group.isStack, !expanded.contains(group.id) {
                return [NotificationFeedItem(entry: group.front, group: group, isCollapsedStack: true)]
            }
            return group.entries.map { NotificationFeedItem(entry: $0, group: group, isCollapsedStack: false) }
        }
    }
}
