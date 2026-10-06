import Foundation

/// Turns the raw texts of a NotificationCenter banner into a feed entry.
///
/// Kept apart from the Accessibility calls so the parsing rules can be tested with plain strings.
nonisolated enum NotificationBannerParser {
    /// The sending app's display name, recovered from the banner's description.
    ///
    /// macOS gives the app no element of its own. The banner's `AXDescription` reads
    /// "App, Title, Subtitle, Body", so the name is whatever precedes the known texts. Matching
    /// the whole suffix keeps a name or a body that contains ", " intact.
    ///
    /// - Returns: nil for a system alert, whose description holds only the texts, and for an
    ///   empty description.
    static func appName(description: String?, title: String?, subtitle: String?, body: String?) -> String? {
        guard let description, !description.isEmpty else { return nil }
        let joined = [title, subtitle, body].compactMap { $0 }.joined(separator: ", ")
        if description == joined { return nil }
        let suffix = ", " + joined
        if !joined.isEmpty, description.hasSuffix(suffix) {
            let name = String(description.dropLast(suffix.count))
            return name.isEmpty ? nil : name
        }
        // An unexpected layout. The first field is the best guess and is shown as a name only.
        return description.components(separatedBy: ", ").first.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Builds an entry, or returns nil while the banner has no text yet.
    static func entry(from reading: NotificationBannerReading, at date: Date) -> NotificationFeedEntry? {
        guard reading.isPopulated else { return nil }
        let title = reading.title.flatMap(nonEmpty)
        let subtitle = reading.subtitle.flatMap(nonEmpty)
        let body = reading.body.flatMap(nonEmpty)
        return NotificationFeedEntry(
            id: reading.id,
            appName: appName(description: reading.description, title: reading.title,
                             subtitle: reading.subtitle, body: reading.body),
            title: title, subtitle: subtitle, body: body, arrivedAt: date)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
