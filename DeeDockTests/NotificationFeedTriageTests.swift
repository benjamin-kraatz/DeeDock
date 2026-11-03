import Foundation
import Testing
@testable import DeeDock

/// DEE-155 triage: grouping by sender, auto-clear on app activation, Clear when closed, swipe
/// geometry, and the count-only analytics.
@Suite("Notification feed triage")
@MainActor
struct NotificationFeedTriageTests {
    private let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    // MARK: - Grouping

    @Test("Groups sit where their newest entry is, and keep entries newest first")
    func groupOrder() {
        let entries = [entry("m1", "Messages"), entry("c1", "Calendar"), entry("m2", "Messages"),
                       entry("x1", "Mail"), entry("s1", nil), entry("x2", "Mail"), entry("s2", nil)]
        let groups = NotificationFeedGrouping.groups(entries)
        #expect(groups.map(\.appName) == ["Messages", "Calendar", "Mail", nil])
        #expect(groups.map { $0.entries.map(\.id) } == [["m1", "m2"], ["c1"], ["x1", "x2"], ["s1", "s2"]])
        #expect(groups.map(\.isStack) == [true, false, true, true])
        #expect(groups[3].id == "system")
    }

    @Test("Names group exactly as macOS spelled them")
    func groupingIsExact() {
        let groups = NotificationFeedGrouping.groups([entry("a", "Notes"), entry("b", "notes")])
        #expect(groups.count == 2)
    }

    @Test("A folded stack is one keyboard item; an unfolded one is a row per entry")
    func itemsFollowFolding() throws {
        let entries = [entry("m1", "Messages"), entry("c1", "Calendar"), entry("m2", "Messages"), entry("m3", "Messages")]
        let groups = NotificationFeedGrouping.groups(entries)
        let folded = NotificationFeedGrouping.items(groups, expanded: [])
        #expect(folded.map(\.id) == ["m1", "c1"])
        #expect(folded.map(\.isCollapsedStack) == [true, false])

        let messages = try #require(groups.first)
        let unfolded = NotificationFeedGrouping.items(groups, expanded: [messages.id])
        #expect(unfolded.map(\.id) == ["m1", "m2", "m3", "c1"])
        #expect(unfolded.map(\.isInExpandedGroup) == [true, true, true, false])
    }

    @Test("Folding a stack moves a selection inside it to the front card")
    func foldingRepairsSelection() throws {
        let entries = [entry("m1", "Messages"), entry("m2", "Messages"), entry("c1", "Calendar")]
        let group = try #require(NotificationFeedGrouping.groups(entries).first)
        let state = NotificationFeedPanelState()
        state.setExpanded(group, true)
        state.selection = "m2"
        state.setExpanded(group, false)
        #expect(state.selection == "m1")
        #expect(state.items(in: entries).map(\.id) == ["m1", "c1"])
    }

    @Test("A stack down to one entry forgets that it was unfolded")
    func pruneExpanded() throws {
        let entries = [entry("m1", "Messages"), entry("m2", "Messages")]
        let group = try #require(NotificationFeedGrouping.groups(entries).first)
        let state = NotificationFeedPanelState()
        state.setExpanded(group, true)
        state.pruneExpanded(in: [entries[0]])
        #expect(state.expanded.isEmpty)
    }

    // MARK: - Auto-clear

    @Test("An activated app clears only entries whose name resolves to exactly that app")
    func autoClearMatchesExactly() {
        let mail = reference("com.apple.mail", "Mail")
        let notesA = reference("com.example.notes", "Notes")
        let notesB = reference("org.other.notes", "Notes")
        let installed = [mail, notesA, notesB]
        let resolve: (String) -> ApplicationReference? = { NotificationFeedAppResolver.unique(named: $0, in: installed) }
        let entries = [entry("1", "Mail"), entry("2", "Notes"), entry("3", nil), entry("4", "mail"), entry("5", "Unknown")]

        #expect(NotificationFeedAutoClear.entryIDs(in: entries, applicationID: mail.id, resolve: resolve) == ["1", "4"])
        // Two installed apps share the name, so neither may claim the entry.
        #expect(NotificationFeedAutoClear.entryIDs(in: entries, applicationID: notesA.id, resolve: resolve).isEmpty)
        #expect(NotificationFeedAutoClear.entryIDs(in: entries, applicationID: "com.example.unknown", resolve: resolve).isEmpty)
    }

    @Test("System alerts are never auto-cleared and each name is resolved once")
    func autoClearSkipsSystem() {
        var lookups: [String] = []
        let any = reference("com.example.any", "Any")
        let entries = [entry("1", nil), entry("2", "Any"), entry("3", "Any"), entry("4", nil)]
        let ids = NotificationFeedAutoClear.entryIDs(in: entries, applicationID: any.id) { name in
            lookups.append(name)
            return any
        }
        #expect(ids == ["2", "3"])
        #expect(lookups == ["Any"])
    }

    @Test("Clearing entries while the feed is closed lowers the badge by the unread ones removed")
    func removalKeepsUnreadExact() {
        let store = NotificationFeedStore()
        store.ingest([reading("old")], at: start)
        store.isViewing = true
        store.isViewing = false
        store.ingest([reading("a"), reading("b")], at: start)
        #expect(store.unreadCount == 2)
        #expect(store.remove(["b", "old", "missing"]) == 2)
        #expect(store.entries.map(\.id) == ["a"])
        #expect(store.unreadCount == 1)
    }

    // MARK: - Clear when closed

    @Test("Closing clears what was seen; arrivals while closed survive and stay unread")
    func clearSeenKeepsArrivalsWhileClosed() {
        let store = NotificationFeedStore()
        store.ingest([reading("before")], at: start)
        store.isViewing = true
        store.ingest([reading("while-open")], at: start)
        store.isViewing = false
        store.ingest([reading("while-closed")], at: start)
        #expect(store.clearSeen() == 2)
        #expect(store.entries.map(\.id) == ["while-closed"])
        #expect(store.unreadCount == 1)
        // A second close with nothing seen in between removes nothing.
        #expect(store.clearSeen() == 0)
    }

    @Test("Each opening starts a new set of seen entries")
    func reopeningResetsSeen() {
        let store = NotificationFeedStore()
        store.ingest([reading("a")], at: start)
        store.isViewing = true
        store.isViewing = false
        store.ingest([reading("b")], at: start)
        store.isViewing = true
        store.remove(["a"])
        store.isViewing = false
        #expect(store.clearSeen() == 1)
        #expect(store.isEmpty)
    }

    @Test("Clear when closed defaults off, also for settings saved before it existed")
    func clearOnCloseSettingDefaultsOff() throws {
        #expect(!DockSettings.defaults.notificationFeedClearsOnClose)
        var enabled = DockSettings.defaults
        enabled.notificationFeedClearsOnClose = true
        let encoded = try JSONEncoder().encode(enabled)
        #expect(try JSONDecoder().decode(DockSettings.self, from: encoded).notificationFeedClearsOnClose)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "notificationFeedClearsOnClose")
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.notificationFeedClearsOnClose)
    }

    // MARK: - Swipe

    @Test("A gesture is claimed only once it is clearly horizontal")
    func swipeIntent() {
        typealias Physics = NotificationFeedSwipePhysics
        #expect(Physics.intent(dx: -3, dy: 0) == nil)
        #expect(Physics.intent(dx: -12, dy: 2) == .horizontal)
        #expect(Physics.intent(dx: -10, dy: -8) == .vertical)
        #expect(Physics.intent(dx: 1, dy: 20) == .vertical)
    }

    @Test("Pulling right rubber-bands and pulling past the row follows a quarter")
    func swipeReveal() {
        typealias Physics = NotificationFeedSwipePhysics
        #expect(Physics.reveal(start: 0, translation: -50, width: 360) == 50)
        #expect(Physics.reveal(start: 72, translation: 20, width: 360) == 52)
        let pulled = Physics.reveal(start: 0, translation: 100, width: 360)
        #expect(pulled < 0 && pulled > -Physics.rubberBand)
        #expect(Physics.reveal(start: 0, translation: -400, width: 360) == 370)
    }

    @Test("Release commits past 40 %, snaps open after half the action, or closes")
    func swipeOutcome() {
        typealias Physics = NotificationFeedSwipePhysics
        #expect(Physics.outcome(reveal: 144, width: 360, velocity: 0) == .commit)
        #expect(Physics.outcome(reveal: 20, width: 360, velocity: -1500) == .commit)
        #expect(Physics.outcome(reveal: 60, width: 360, velocity: 0) == .reveal)
        #expect(Physics.outcome(reveal: 60, width: 360, velocity: 600) == .close)
        #expect(Physics.outcome(reveal: 20, width: 360, velocity: 0) == .close)
    }

    // MARK: - Analytics

    @Test("Triage events carry counts and closed vocabularies only")
    func analyticsRecords() {
        let opened = AnalyticsEvent.notificationFeedRowOpened(trigger: .keyboard, clearedCount: 3).record
        #expect(opened.name == "notification_feed_row_opened")
        #expect(opened.properties["trigger"] == AnalyticsValue(AnalyticsTrigger.keyboard))
        #expect(opened.properties["cleared_count"] == AnalyticsValue(3))

        let removed = AnalyticsEvent.notificationFeedRowRemoved(method: .hoverX).record
        #expect(removed.name == "notification_feed_row_removed")
        #expect(removed.properties["method"] == AnalyticsValue(AnalyticsNotificationFeedRemoval.hoverX))

        let group = AnalyticsEvent.notificationFeedGroupCleared(method: .swipe, count: 4).record
        #expect(group.name == "notification_feed_group_cleared")
        #expect(group.properties["count"] == AnalyticsValue(4))

        let all = AnalyticsEvent.notificationFeedClearedAll(source: .tileMenu, count: 9).record
        #expect(all.name == "notification_feed_cleared_all")
        #expect(all.properties["source"] == AnalyticsValue(AnalyticsNotificationFeedClearSource.tileMenu))
        #expect(all.properties["count"] == AnalyticsValue(9))

        let auto = AnalyticsEvent.notificationFeedAutoCleared(count: 2).record
        #expect(auto.name == "notification_feed_auto_cleared")
        #expect(Set(auto.properties.values.keys) == ["count"])
    }

    @Test("Removal methods and clear sources use the documented tokens")
    func analyticsTokens() {
        #expect(AnalyticsNotificationFeedRemoval.allCases.map(\.rawValue)
                == ["hover_x", "swipe", "menu", "keyboard", "voice_over"])
        #expect(AnalyticsNotificationFeedClearSource.allCases.map(\.rawValue)
                == ["header", "keyboard", "tile_menu", "voice_over", "settings"])
    }

    @Test("Removing and clearing report how many entries left")
    func removalCounts() {
        let store = NotificationFeedStore()
        store.ingest([reading("a"), reading("b"), reading("c")], at: start)
        #expect(store.remove(["a", "a2"]) == 1)
        #expect(store.clear() == 2)
        #expect(store.clear() == 0)
    }

    // MARK: - Fixtures

    private func entry(_ id: String, _ app: String?) -> NotificationFeedEntry {
        NotificationFeedEntry(id: id, appName: app, title: "Title", subtitle: nil, body: "Body", arrivedAt: start)
    }

    private func reading(_ id: String) -> NotificationBannerReading {
        NotificationBannerReading(id: id, description: "App, Title \(id), Body", title: "Title \(id)",
                                  subtitle: nil, body: "Body")
    }

    private func reference(_ bundleID: String, _ name: String) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: bundleID, url: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
                             name: name)
    }
}
