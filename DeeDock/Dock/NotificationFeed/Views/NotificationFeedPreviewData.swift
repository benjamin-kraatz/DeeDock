#if DEBUG
import Foundation

/// Fixed entries for previews. No reader, no live workspace state, no real notifications.
enum NotificationFeedPreviewData {
    static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    static let entries: [NotificationFeedEntry] = [
        NotificationFeedEntry(id: "preview-1", appName: "Messages", title: "Alex Rivera", subtitle: nil,
                              body: "Running ten minutes late, save me a seat by the window?",
                              arrivedAt: now.addingTimeInterval(-40)),
        NotificationFeedEntry(id: "preview-2", appName: "Calendar", title: "Design review",
                              subtitle: "Today at 15:00",
                              body: "Room 4B, starts in 15 minutes.",
                              arrivedAt: now.addingTimeInterval(-6 * 60)),
        NotificationFeedEntry(id: "preview-3", appName: "Mail", title: "Invoice #2041 is ready",
                              subtitle: "billing@example.com",
                              body: "Your invoice for September, 348 items, 2.1 GB total, is attached. Reply to this message if anything looks off.",
                              arrivedAt: now.addingTimeInterval(-52 * 60)),
        NotificationFeedEntry(id: "preview-4", appName: nil, title: "“Weather” Would Like to Send You Notifications",
                              subtitle: nil, body: "Notifications may include alerts, sounds, and icon badges.",
                              arrivedAt: now.addingTimeInterval(-3 * 3600)),
    ]

    @MainActor
    static func state() -> NotificationFeedPanelState {
        NotificationFeedPanelState(unreadOnOpen: ["preview-1"])
    }
}
#endif
