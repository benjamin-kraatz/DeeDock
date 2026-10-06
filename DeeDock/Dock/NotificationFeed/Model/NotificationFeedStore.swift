import Foundation
import Observation

/// The collected notifications, newest first, held in memory only.
///
/// Deduplicates by banner identifier, so repeated reads of one banner, and a notification that
/// reappears in the Notification Center sidebar, never add a second entry. Both the entries and
/// the set of identifiers already seen are bounded. Nothing here is persisted: disabling the
/// feature or quitting DOKK forgets every entry.
@MainActor @Observable
final class NotificationFeedStore {
    /// The most entries the feed keeps. The oldest is dropped first.
    static let capacity = 100
    /// How many banner identifiers are remembered for deduplication after their entry is gone.
    static let seenCapacity = 512

    private(set) var entries: [NotificationFeedEntry] = []
    /// Entries that arrived since the feed was last opened. Drives the tile's badge.
    private(set) var unreadCount = 0
    /// True while the feed's popover is open. Arrivals the person can already see are not unread.
    var isViewing = false {
        didSet { if isViewing { markAllRead() } }
    }
    /// Identifiers in arrival order, so the oldest can be forgotten first.
    @ObservationIgnored private var seenOrder: [String] = []
    @ObservationIgnored private var seen: Set<String> = []

    var isEmpty: Bool { entries.isEmpty }

    /// Adds the banners not seen before and returns how many were added.
    ///
    /// Unpopulated readings are skipped without being remembered, so a later pass can still
    /// collect them once macOS has filled their text in.
    @discardableResult
    func ingest(_ readings: [NotificationBannerReading], at date: Date) -> Int {
        var added: [NotificationFeedEntry] = []
        for reading in readings where !seen.contains(reading.id) {
            guard let entry = NotificationBannerParser.entry(from: reading, at: date) else { continue }
            remember(reading.id)
            added.append(entry)
        }
        guard !added.isEmpty else { return 0 }
        // Batches are newest first. A batch almost always holds one banner; when several arrive in
        // one pass, their on-screen order is kept because the tree carries no arrival time.
        entries.insert(contentsOf: added, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        if !isViewing { unreadCount = min(unreadCount + added.count, entries.count) }
        return added.count
    }

    /// Opening the feed counts as reading everything in it.
    func markAllRead() {
        if unreadCount != 0 { unreadCount = 0 }
    }

    /// Removes one entry. Its identifier stays remembered, so the same banner is not re-added.
    func remove(_ id: NotificationFeedEntry.ID) {
        entries.removeAll { $0.id == id }
        unreadCount = min(unreadCount, entries.count)
    }

    /// Empties the feed. Identifiers stay remembered, so banners still on screen are not re-added.
    func clear() {
        entries.removeAll()
        unreadCount = 0
    }

    /// Forgets entries and identifiers. Used when the feature turns off.
    func reset() {
        clear()
        seen.removeAll()
        seenOrder.removeAll()
    }

    private func remember(_ id: String) {
        seen.insert(id)
        seenOrder.append(id)
        if seenOrder.count > Self.seenCapacity {
            let overflow = seenOrder.count - Self.seenCapacity
            seenOrder.prefix(overflow).forEach { seen.remove($0) }
            seenOrder.removeFirst(overflow)
        }
    }
}
