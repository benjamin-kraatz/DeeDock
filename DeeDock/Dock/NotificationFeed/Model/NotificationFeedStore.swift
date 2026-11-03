import Foundation
import Observation

/// The collected notifications, newest first, held in memory only.
///
/// Deduplicates by banner identifier, so repeated reads of one banner, and a notification that
/// reappears in the Notification Center sidebar, never add a second entry. Both the entries and
/// the set of identifiers already seen are bounded. Nothing here is persisted: disabling the
/// feature or quitting DOKK forgets every entry.
///
/// Unread entries are always the newest ones, so the unread count doubles as a prefix length.
/// Every removal keeps that true by subtracting the unread entries it took.
@MainActor @Observable
final class NotificationFeedStore {
    /// The most entries the feed keeps. The oldest is dropped first.
    static let capacity = 100
    /// How many banner identifiers are remembered for deduplication after their entry is gone.
    static let seenCapacity = 512

    private(set) var entries: [NotificationFeedEntry] = [] {
        didSet {
            // Entries evicted by the cap or removed can no longer be cleared, so the seen set
            // only ever holds entries the feed still has.
            if !seenWhileViewing.isEmpty {
                seenWhileViewing.formIntersection(entries.lazy.map(\.id))
            }
            entriesDidChange?(oldValue, entries)
        }
    }
    /// Called after every change to ``entries`` with the previous and current entries, in the
    /// same transaction. The notification feed coordinator sets it while the popover is open so
    /// the panel's selection follows arrivals and evictions, and clears it on close.
    @ObservationIgnored var entriesDidChange: ((_ previous: [NotificationFeedEntry], _ current: [NotificationFeedEntry]) -> Void)?
    /// Entries that arrived since the feed was last opened. Drives the tile's badge.
    private(set) var unreadCount = 0
    /// True while the feed's popover is open. Arrivals the person can already see are not unread.
    ///
    /// Opening starts a new viewing session: everything in the feed then, and everything that
    /// arrives while it stays open, counts as seen for ``clearSeen()``.
    var isViewing = false {
        didSet {
            guard isViewing, !oldValue else { return }
            markAllRead()
            seenWhileViewing = Set(entries.map(\.id))
        }
    }
    /// Entries shown during the current or last viewing session that are still in the feed.
    /// Read by ``clearSeen()``. Never larger than ``capacity``.
    @ObservationIgnored private(set) var seenWhileViewing: Set<NotificationFeedEntry.ID> = []
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
        // One assignment, so observers see a single change that already respects the cap.
        if isViewing { seenWhileViewing.formUnion(added.map(\.id)) }
        entries = Array((added + entries).prefix(Self.capacity))
        if !isViewing { unreadCount = min(unreadCount + added.count, entries.count) }
        return added.count
    }

    /// Opening the feed counts as reading everything in it.
    func markAllRead() {
        if unreadCount != 0 { unreadCount = 0 }
    }

    /// Removes one entry. Its identifier stays remembered, so the same banner is not re-added.
    func remove(_ id: NotificationFeedEntry.ID) {
        remove([id])
    }

    /// Removes the entries with these identifiers and returns how many were in the feed.
    ///
    /// Identifiers stay remembered, so a banner still on screen is not re-added. The unread
    /// count drops by the unread entries removed, which keeps the tile's badge exact when an
    /// app is opened while the feed is closed.
    @discardableResult
    func remove(_ ids: Set<NotificationFeedEntry.ID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        let removedUnread = entries.prefix(unreadCount).count(where: { ids.contains($0.id) })
        let before = entries.count
        entries.removeAll { ids.contains($0.id) }
        unreadCount = min(unreadCount - removedUnread, entries.count)
        return before - entries.count
    }

    /// Removes every entry that was shown while the feed was last open, for **Clear when closed**,
    /// and returns how many left.
    ///
    /// Entries that arrived after the feed closed were never seen, so they stay and remain unread.
    @discardableResult
    func clearSeen() -> Int {
        let seen = seenWhileViewing
        seenWhileViewing = []
        return remove(seen)
    }

    /// Empties the feed. Identifiers stay remembered, so banners still on screen are not re-added.
    @discardableResult
    func clear() -> Int {
        let count = entries.count
        entries.removeAll()
        unreadCount = 0
        return count
    }

    /// Forgets entries and identifiers. Used when the feature turns off.
    func reset() {
        clear()
        seenWhileViewing.removeAll()
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
