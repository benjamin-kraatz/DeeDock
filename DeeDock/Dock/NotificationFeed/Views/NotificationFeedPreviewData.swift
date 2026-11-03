#if DEBUG
import Foundation

/// Fixed entries for previews. No reader, no live workspace state, no real notifications.
enum NotificationFeedPreviewData {
    static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    /// The mockup's opening feed: Messages ×2, Calendar, Mail ×3, Slack, and a system alert.
    /// Grouped, Messages and Mail form stacks.
    static let entries: [NotificationFeedEntry] = [
        entry("preview-1", "Messages", "Alex Rivera", nil,
              "Running ten minutes late, save me a seat by the window?", ago: 40),
        entry("preview-2", "Calendar", "Design review", "Today at 15:00", "Room 4B, starts in 15 minutes.", ago: 6 * 60),
        entry("preview-3", "Messages", "Jonas", nil, "Bist du schon da? Ich steh vorm Eingang.", ago: 12 * 60),
        entry("preview-4", "Mail", "Invoice #2041 is ready", "billing@example.com",
              "Your invoice for September, 348 items, 2.1 GB total, is attached. Reply to this message if anything looks off.",
              ago: 52 * 60),
        entry("preview-5", "Slack", "#dokk-releases", "Release bot",
              "1.8.2 draft is up. Checks green, waiting for a reviewer.", ago: 58 * 60),
        entry("preview-6", "Mail", "Rechnung Oktober", "buchhaltung@example.de",
              "Anbei die Rechnung für Oktober. Bitte bis zum 15. begleichen, danke!", ago: 75 * 60),
        entry("preview-7", "Mail", "Your order has shipped", "orders@example.com",
              "Tracking number 1Z 999 AA1 01 2345 6784. Expected Thursday.", ago: 95 * 60),
        entry("preview-8", nil, "“Weather” Would Like to Send You Notifications", nil,
              "Notifications may include alerts, sounds, and icon badges.", ago: 3 * 3600),
    ]

    /// One entry per sender, so nothing stacks.
    static let singleEntries: [NotificationFeedEntry] = [entries[0], entries[1], entries[3], entries[4], entries[7]]

    @MainActor
    static func state() -> NotificationFeedPanelState {
        NotificationFeedPanelState(unreadOnOpen: ["preview-1"])
    }

    private static func entry(_ id: String, _ app: String?, _ title: String?, _ subtitle: String?, _ body: String?,
                              ago seconds: TimeInterval) -> NotificationFeedEntry {
        NotificationFeedEntry(id: id, appName: app, title: title, subtitle: subtitle, body: body,
                              arrivedAt: now.addingTimeInterval(-seconds))
    }
}
#endif
