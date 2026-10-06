import Foundation
import Testing
@testable import DeeDock

/// Banner parsing and the feed's bounded, deduplicating store.
///
/// The parser cases come from descriptions the AXonNC prototype read on macOS 27.0.1.
@Suite("Notification feed")
@MainActor
struct NotificationFeedTests {
    private let start = Date(timeIntervalSinceReferenceDate: 812_000_000)

    @Test("The app name is the description's prefix before the banner texts")
    func appNameFromDescription() {
        #expect(NotificationBannerParser.appName(description: "Skripteditor, Third Title, Sub, Third body",
                                                 title: "Third Title", subtitle: "Sub", body: "Third body") == "Skripteditor")
        #expect(NotificationBannerParser.appName(description: "Mail, Invoice, Hello",
                                                 title: "Invoice", subtitle: nil, body: "Hello") == "Mail")
    }

    @Test("Commas inside the body or the app name do not split the name")
    func commasStayIntact() {
        let body = "348 files copied, 2.1 GB total."
        #expect(NotificationBannerParser.appName(description: "Finder, Copy finished, \(body)",
                                                 title: "Copy finished", subtitle: nil, body: body) == "Finder")
        #expect(NotificationBannerParser.appName(description: "Acme, Inc. Sync, Done, Ready",
                                                 title: "Done", subtitle: nil, body: "Ready") == "Acme, Inc. Sync")
    }

    @Test("A system alert names no app")
    func systemAlertHasNoApp() {
        let title = "“Weather” Would Like to Send You Notifications"
        let body = "Notifications may include alerts, sounds, and icon badges."
        #expect(NotificationBannerParser.appName(description: "\(title), \(body)",
                                                 title: title, subtitle: nil, body: body) == nil)
        #expect(NotificationBannerParser.appName(description: "", title: "A", subtitle: nil, body: nil) == nil)
        #expect(NotificationBannerParser.appName(description: nil, title: "A", subtitle: nil, body: nil) == nil)
    }

    @Test("A banner without text yet is skipped and collected on a later pass")
    func unpopulatedBannerIsRetried() {
        let store = NotificationFeedStore()
        let empty = NotificationBannerReading(id: "a", description: nil, title: nil, subtitle: nil, body: nil)
        #expect(store.ingest([empty], at: start) == 0)
        #expect(store.isEmpty)
        #expect(store.ingest([reading("a")], at: start) == 1)
        #expect(store.entries.map(\.id) == ["a"])
    }

    @Test("Repeated reads of one banner add one entry, newest batch first")
    func deduplicatesAndOrders() {
        let store = NotificationFeedStore()
        store.ingest([reading("first")], at: start)
        store.ingest([reading("first"), reading("second")], at: start.addingTimeInterval(2))
        store.ingest([reading("second")], at: start.addingTimeInterval(3))
        #expect(store.entries.map(\.id) == ["second", "first"])
        #expect(store.unreadCount == 2)
    }

    @Test("A removed or cleared banner still on screen is not collected again")
    func removedBannersStaySeen() {
        let store = NotificationFeedStore()
        store.ingest([reading("a"), reading("b")], at: start)
        store.remove("a")
        store.ingest([reading("a")], at: start)
        #expect(store.entries.map(\.id) == ["b"])
        store.clear()
        store.ingest([reading("b")], at: start)
        #expect(store.isEmpty)
        #expect(store.unreadCount == 0)
    }

    @Test("Turning the feed off forgets entries and identifiers")
    func resetForgetsEverything() {
        let store = NotificationFeedStore()
        store.ingest([reading("a")], at: start)
        store.reset()
        #expect(store.isEmpty)
        #expect(store.ingest([reading("a")], at: start) == 1)
    }

    @Test("Opening the feed reads everything, and arrivals while it is open stay read")
    func viewingClearsUnread() {
        let store = NotificationFeedStore()
        store.ingest([reading("a"), reading("b")], at: start)
        #expect(store.unreadCount == 2)
        store.isViewing = true
        #expect(store.unreadCount == 0)
        store.ingest([reading("c")], at: start)
        #expect(store.unreadCount == 0)
        store.isViewing = false
        store.ingest([reading("d")], at: start)
        #expect(store.unreadCount == 1)
    }

    @Test("The feed keeps at most its capacity, dropping the oldest")
    func capacityDropsOldest() {
        let store = NotificationFeedStore()
        let total = NotificationFeedStore.capacity + 5
        for index in 0..<total {
            store.ingest([reading("n\(index)")], at: start.addingTimeInterval(Double(index)))
        }
        #expect(store.entries.count == NotificationFeedStore.capacity)
        #expect(store.entries.first?.id == "n\(total - 1)")
        #expect(store.entries.last?.id == "n5")
        #expect(store.unreadCount == NotificationFeedStore.capacity)
    }

    @Test("Only one unambiguous application resolves from a banner's name")
    func resolvesOnlyUniqueNames() {
        let mail = ApplicationReference(bundleIdentifier: "com.apple.mail",
                                        url: URL(fileURLWithPath: "/System/Applications/Mail.app"), name: "Mail")
        let notesA = ApplicationReference(bundleIdentifier: "com.example.notes",
                                          url: URL(fileURLWithPath: "/Applications/Notes.app"), name: "Notes")
        let notesB = ApplicationReference(bundleIdentifier: "org.other.notes",
                                          url: URL(fileURLWithPath: "/Applications/Other Notes.app"), name: "Notes")
        let references = [mail, notesA, notesB, mail]
        #expect(NotificationFeedAppResolver.unique(named: "mail", in: references)?.id == mail.id)
        #expect(NotificationFeedAppResolver.unique(named: "Notes", in: references) == nil)
        #expect(NotificationFeedAppResolver.unique(named: "Calendar", in: references) == nil)
    }

    @Test("Settings saved before the feed existed keep it off")
    func settingDefaultsOff() throws {
        let encoded = try JSONEncoder().encode(DockSettings.defaults)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "showNotificationFeed")
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.showNotificationFeed)
        var enabled = DockSettings.defaults
        enabled.showNotificationFeed = true
        #expect(try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(enabled)) == enabled)
    }

    @Test("The Accessibility check runs only while access is missing")
    func accessCheckStopsOnceGranted() {
        var trusted = false
        let controller = NotificationFeedController(isTrusted: { trusted }, notificationCenterPID: { nil })
        defer { controller.stop() }
        controller.configure(enabled: true)
        #expect(controller.state == .needsAccess)
        #expect(controller.isCheckingAccess)

        trusted = true
        controller.refreshAccess()
        #expect(!controller.isCheckingAccess)
        // No NotificationCenter process in this test, so the reader waits for its launch.
        #expect(controller.state == .waiting)

        trusted = false
        controller.refreshAccess()
        #expect(controller.state == .needsAccess)
        #expect(controller.isCheckingAccess)
    }

    @Test("Turning the feed off stops the Accessibility check")
    func accessCheckStopsWhenDisabled() {
        let controller = NotificationFeedController(isTrusted: { false }, notificationCenterPID: { nil })
        controller.configure(enabled: true)
        #expect(controller.isCheckingAccess)
        controller.configure(enabled: false)
        #expect(!controller.isCheckingAccess)
        #expect(controller.state == .off)
    }

    private func reading(_ id: String) -> NotificationBannerReading {
        NotificationBannerReading(id: id, description: "App, Title \(id), Body", title: "Title \(id)",
                                  subtitle: nil, body: "Body")
    }
}
