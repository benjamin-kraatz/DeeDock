import Foundation

/// What a Line icon dock's tooltip says about a badged tile, beside and under its name.
///
/// The ring only says that something is new. Pointing at the tile says how much and, when the
/// Notification Feed has collected one, what. Native icon docks keep their plain tooltip, because
/// their corner badge already shows the count.
struct DockTooltipBadge: Equatable {
    /// "2 new", "New", or a standing count; nil adds nothing beside the name.
    var summary: String?
    /// Draws the summary in red, matching the ring.
    var isNew: Bool
    /// The newest collected banner from this app since its badge was acknowledged.
    var banner: String?

    /// The detail for `slot`, or nil when its tile shows no badge or its dock draws native artwork.
    @MainActor init?(slot: DockRenderSlot, interaction: DockInteraction) {
        guard interaction.iconStyle == .line else { return nil }
        switch slot {
        case .app(let item):
            guard item.isAvailable, let badges = interaction.badges,
                  interaction.lineIcon(for: item.reference, artwork: item.icon) != nil else { return nil }
            let key = DockBadgePath.key(for: item.resolvedURL ?? item.reference.url)
            guard let label = badges.labels[key] else { return nil }
            let isNew = badges.attention.isNew(key: key, label: label)
            let since = badges.attention.acknowledgedDate(key: key) ?? .distantPast
            // The banner names no application, only its display name, so a name match is the best
            // available link. Two apps sharing a name would share a preview.
            let entry = isNew ? interaction.notificationFeed?.store.entries.first {
                $0.arrivedAt > since
                    && $0.appName?.compare(item.reference.name, options: .caseInsensitive) == .orderedSame
            } : nil
            self.init(summary: Self.summary(label: label, isNew: isNew), isNew: isNew,
                      banner: entry.flatMap { Self.preview([$0.title, $0.subtitle ?? $0.body]) })
        case .notificationFeed:
            guard let store = interaction.notificationFeed?.store, store.unreadCount > 0,
                  interaction.lineIcon(for: .notificationFeed) != nil else { return nil }
            self.init(summary: String(localized: .tooltipBadgeNewCount(store.unreadCount)), isNew: true,
                      banner: store.entries.first.flatMap { Self.preview([$0.appName, $0.title ?? $0.body]) })
        default:
            return nil
        }
    }

    init(summary: String?, isNew: Bool, banner: String?) {
        self.summary = summary
        self.isNew = isNew
        self.banner = banner
    }

    /// A count reads as "2 new" while it is news and as the bare number once seen. Other labels,
    /// such as a dot, read as "New" and are left out once seen.
    static func summary(label: String, isNew: Bool) -> String? {
        if case .count(let count) = BadgeObservation(label: label) {
            return isNew ? String(localized: .tooltipBadgeNewCount(Int(count))) : count.formatted()
        }
        return isNew ? String(localized: .tooltipBadgeNew) : nil
    }

    /// Joins the parts a banner has into one line, or nil when it has none.
    private static func preview(_ parts: [String?]) -> String? {
        let text = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        return text.isEmpty ? nil : text
    }
}
