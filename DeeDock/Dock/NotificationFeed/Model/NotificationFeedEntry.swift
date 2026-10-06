import Foundation

/// The texts one NotificationCenter banner exposed during a single Accessibility pass.
///
/// Plain values copied on the reader's queue. No Accessibility handle survives into this type.
/// `id` is the banner's `AXIdentifier`, a UUID that macOS keeps for the notification's lifetime,
/// including when the same notification later appears in the Notification Center sidebar.
nonisolated struct NotificationBannerReading: Equatable, Sendable {
    let id: String
    /// The banner's `AXDescription`, which reads "App, Title, Subtitle, Body".
    let description: String?
    let title: String?
    let subtitle: String?
    let body: String?

    /// False while macOS is still filling the banner in; a later pass reads it again.
    var isPopulated: Bool { title != nil || body != nil || description != nil }
}

/// One notification the feed collected, as the person sees it in the popover.
///
/// Lives only in memory. Notification text is message content: it is never written to disk,
/// logged, or passed to analytics.
nonisolated struct NotificationFeedEntry: Identifiable, Equatable, Sendable {
    /// The banner's `AXIdentifier`. Deduplicates repeat reads of one banner.
    let id: String
    /// The localized display name parsed from the banner, or nil for a system alert.
    /// macOS supplies no bundle identifier, so this is a name and nothing more.
    let appName: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let arrivedAt: Date
}
