import Foundation

/// The new notification a Line icon dock's hover label previews, carried into the app's Window Peek.
///
/// Built from the same Notification Feed entry as the label, so the strip in Peek never says more or
/// less than the label it replaces. Banner text is message content: it stays in memory and is never
/// logged or sent to analytics.
struct WindowPeekNotice: Equatable {
    /// "1 new" or "New", as the label shows it.
    let summary: String
    /// The banner's title, usually the sender, or the app's name when the banner had none.
    let sender: String
    /// The banner's subtitle or body, or nil when it had neither.
    let message: String?

    /// The notice for a badge detail, or nil unless the badge is new and the label shows a banner.
    init?(badge: DockTooltipBadge, appName: String) {
        guard badge.isNew, badge.banner != nil, let summary = badge.summary, let entry = badge.entry else { return nil }
        // The same parts the label joins, so both read the same banner.
        let title = Self.text(entry.title)
        let message = Self.text(entry.subtitle ?? entry.body)
        guard title != nil || message != nil else { return nil }
        self.init(summary: summary, sender: title ?? appName, message: message)
    }

    init(summary: String, sender: String, message: String?) {
        self.summary = summary
        self.sender = sender
        self.message = message
    }

    /// The banner as the label shows it, for VoiceOver.
    var spoken: String { [sender, message].compactMap { $0 }.joined(separator: ": ") }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// What a dock hands Window Peek for a badged tile when Peek opens over it.
struct WindowPeekNoticeHandoff {
    /// The hover label as it stood when Peek took over, in AppKit screen coordinates.
    struct Label {
        let frame: CGRect
        let artwork: DockTooltipArtwork
    }

    let notice: WindowPeekNotice
    /// Nil when the label was not on screen, for example before its delay ran out. Peek then shows
    /// the notice in place without a flight.
    let label: Label?
}
