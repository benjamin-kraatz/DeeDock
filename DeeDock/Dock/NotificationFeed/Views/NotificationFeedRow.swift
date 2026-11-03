import SwiftUI

/// Where a row sits: alone, or at a position in a sender's stack, folded or unfolded.
nonisolated struct NotificationFeedRowPlacement: Equatable, Sendable {
    /// Position in the sender's group, newest first.
    var index = 0
    /// Entries in the sender's group.
    var count = 1
    /// The group is a stack the person has not unfolded.
    var isFolded = false

    static let single = NotificationFeedRowPlacement()

    /// The card in front of a folded stack: count capsule, hairline, click unfolds.
    var isStackFront: Bool { isFolded && count > 1 && index == 0 }
    /// A card behind a folded stack. Only its bottom edge shows.
    var isPeek: Bool { isFolded && index > 0 }
    /// Folded stacks draw at most three cards; the rest wait out of sight.
    var isHiddenInStack: Bool { isFolded && index >= NotificationFeedGrouping.maximumStackDepth }
    /// How many steps behind the front card this card is drawn, at most two.
    var depth: Int { min(index, NotificationFeedGrouping.maximumStackDepth - 1) }
}

/// The commands a row offers. The panel decides what each means for a row or a stack.
struct NotificationFeedRowActions {
    /// A click: unfold a stack, or open the sender's app.
    var primary: () -> Void = {}
    /// Nil when the sender resolves to no single app.
    var open: (() -> Void)?
    var copy: () -> Void = {}
    /// Removes the entry, or clears the whole stack from its front card.
    var dismiss: (AnalyticsNotificationFeedRemoval) -> Void = { _ in }
    /// Offered on a folded stack's front card.
    var expand: (() -> Void)?
    /// Offered on the rows of an unfolded stack.
    var collapse: (() -> Void)?
}

/// One collected banner: sender, arrival time, and the texts macOS showed.
///
/// The same view draws a lone row, the front card of a folded stack with its count, and the
/// cards peeking out beneath it, so a row keeps its identity while its stack folds and unfolds.
/// Hovering reveals a ✕. Notification text and app names come from macOS and are shown
/// verbatim, never translated.
struct NotificationFeedRow: View {
    let entry: NotificationFeedEntry
    /// The resolved sender's icon, or nil for a system alert or an ambiguous name.
    let icon: NSImage?
    let now: Date
    /// The entry arrived since the feed was last opened.
    let isNew: Bool
    let isSelected: Bool
    var placement: NotificationFeedRowPlacement = .single
    /// Swaps the text fade of a folding or unfolding card for the 150 ms cross-fade. Passed down
    /// from the panel rather than read here, so previews can force it.
    var reduceMotion = false
    let actions: NotificationFeedRowActions

    @Environment(\.locale) private var locale
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NotificationFeedSenderIcon(icon: icon, isSystem: entry.appName == nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isNew {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    if placement.isStackFront {
                        NotificationFeedCountCapsule(count: placement.count)
                            .transition(.opacity.animation(NotificationFeedMotion.contentFade(reduceMotion: reduceMotion)))
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: arrival(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .opacity(hovered ? 0 : 1)
                }
                if let title = entry.title {
                    Text(verbatim: title).font(.callout.weight(.semibold)).lineLimit(2)
                }
                if let subtitle = entry.subtitle {
                    Text(verbatim: subtitle).font(.callout).lineLimit(1)
                }
                if let body = entry.body {
                    Text(verbatim: body).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        // A peeking card shows no text, only its edge; the text fades in as the stack unfolds.
        // Its own curve, so it also fades under Reduce Motion, where the layout does not animate.
        .opacity(placement.isPeek ? 0 : 1)
        .animation(NotificationFeedMotion.contentFade(reduceMotion: reduceMotion), value: placement.isPeek)
        // Fill whatever height the stack proposes, so a peeking card matches the front card.
        .frame(maxHeight: .infinity, alignment: .top)
        .background { background }
        .overlay(alignment: .topTrailing) {
            if hovered && !placement.isPeek {
                Button { actions.dismiss(.hoverX) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(placement.isStackFront ? Text(.notificationFeedClearGroup(placement.count))
                                             : Text(.notificationFeedRemove))
                .padding(6)
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .clipShape(NotificationFeedPeekBand(folded: placement.isPeek ? 1 : 0,
                                            band: NotificationFeedStackLayout.peekStep * CGFloat(max(placement.depth, 1)) + 1))
        .opacity(placement.isHiddenInStack ? 0 : 1)
        .allowsHitTesting(!placement.isPeek)
        .contentShape(.rect(cornerRadius: 12))
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
        .onTapGesture(perform: actions.primary)
        .contextMenu { menu }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(placement.isStackFront ? Text(.notificationFeedStackHint) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityActions { accessibilityActions }
        // Last, so it hides the element built above; before it, peeking cards were still read.
        .accessibilityHidden(placement.isPeek)
    }

    // MARK: - Menus and actions

    @ViewBuilder private var menu: some View {
        if let open = actions.open {
            Button { Analytics.performing(.menu, open) } label: {
                Label { Text(.notificationFeedOpenApp) } icon: { Image(systemName: "arrow.up.forward.app") }
            }
        }
        Button(action: actions.copy) { Label { Text(.notificationFeedCopy) } icon: { Image(systemName: "doc.on.doc") } }
        Divider()
        Button(role: .destructive) { actions.dismiss(.menu) } label: {
            Label { placement.isStackFront ? Text(.notificationFeedClearGroup(placement.count)) : Text(.notificationFeedRemove) }
                icon: { Image(systemName: "xmark") }
        }
    }

    @ViewBuilder private var accessibilityActions: some View {
        if let open = actions.open {
            Button { Analytics.performing(.voiceOver, open) } label: { Text(.notificationFeedOpenApp) }
        }
        if let expand = actions.expand {
            Button(action: expand) { Text(.notificationFeedExpand) }
        }
        if let collapse = actions.collapse {
            Button(action: collapse) { Text(.notificationFeedShowLess) }
        }
        Button(action: actions.copy) { Text(.notificationFeedCopy) }
        Button { actions.dismiss(.voiceOver) } label: {
            placement.isStackFront ? Text(.notificationFeedClearAction) : Text(.notificationFeedRemove)
        }
    }

    private var helpText: Text {
        if placement.isStackFront { return Text(.notificationFeedStackHint) }
        return actions.open != nil ? Text(.notificationFeedOpenAppHelp) : Text(verbatim: "")
    }

    // MARK: - Text

    private var senderName: String {
        entry.appName ?? localized(.notificationFeedSystemSender)
    }

    /// Relative to the panel's clock rather than the system's, so previews stay fixed.
    private func arrival(_ style: RelativeDateTimeFormatter.UnitsStyle) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = style
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: entry.arrivedAt, relativeTo: max(now, entry.arrivedAt))
    }

    /// Time and every text in reading order, so VoiceOver reads the banner as one item.
    private var bannerText: String {
        ([arrival(.full)] + [entry.title, entry.subtitle, entry.body].compactMap { $0 }).joined(separator: ", ")
    }

    /// A folded stack reads as "Mail, 3 notifications"; a row reads as its sender and banner.
    private var accessibilityLabel: Text {
        if placement.isStackFront {
            return Text(verbatim: senderName + ", " + localized(.notificationFeedEntryCount(placement.count)))
        }
        return Text(verbatim: senderName + ", " + bannerText)
    }

    /// A stack's value is its newest banner, after the new marker when it applies.
    private var accessibilityValue: Text {
        let marker = isNew ? localized(.notificationFeedNewMarker) : nil
        guard placement.isStackFront else { return Text(verbatim: marker ?? "") }
        return Text(verbatim: [marker, bannerText].compactMap { $0 }.joined(separator: ", "))
    }

    /// Resolves app-owned copy in the view's locale, for labels joined with text from macOS.
    private func localized(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    // MARK: - Drawing

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if isSelected && !placement.isPeek {
            shape.fill(Color.accentColor.opacity(hovered ? 0.22 : 0.18))
                .overlay { shape.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5) }
        } else if placement.isPeek {
            // The mockup's peek fills: the nearer card a touch brighter than the one behind it.
            shape.fill(.primary.opacity(placement.depth == 1 ? 0.07 : 0.045))
                .overlay { shape.strokeBorder(.primary.opacity(0.085), lineWidth: 0.5) }
        } else {
            shape.fill(.primary.opacity(hovered ? 0.08 : 0.04))
                .overlay {
                    if placement.isStackFront { shape.strokeBorder(.primary.opacity(0.085), lineWidth: 0.5) }
                }
        }
    }
}

/// How many entries a folded stack holds, beside the sender's name.
struct NotificationFeedCountCapsule: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 9.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(height: 13)
            .background(.primary.opacity(0.085), in: .capsule)
            .contentTransition(.numericText(value: Double(count)))
            .accessibilityHidden(true)
    }
}

/// Clips a card to its bottom edge while it peeks out from under a folded stack, and opens up to
/// the whole card as the stack unfolds. Animating `folded` slides the clip with the layout.
private struct NotificationFeedPeekBand: Shape {
    /// 1 shows only the bottom `band` points; 0 shows the whole card.
    var folded: CGFloat
    let band: CGFloat

    var animatableData: CGFloat {
        get { folded }
        set { folded = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = folded * max(0, rect.height - band)
        return Path(CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: rect.height - top))
    }
}

/// The sender's app icon, a system badge for alerts, or a neutral placeholder when the name
/// matches no single installed app.
private struct NotificationFeedSenderIcon: View {
    let icon: NSImage?
    let isSystem: Bool

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: isSystem ? "gearshape.fill" : "app.badge")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(2)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Rows") {
    let entries = NotificationFeedPreviewData.entries
    VStack(spacing: 6) {
        NotificationFeedRow(entry: entries[0], icon: nil, now: NotificationFeedPreviewData.now,
                            isNew: true, isSelected: false, actions: .init(open: {}))
        NotificationFeedRow(entry: entries[3], icon: nil, now: NotificationFeedPreviewData.now,
                            isNew: false, isSelected: true,
                            placement: .init(index: 0, count: 3, isFolded: true), actions: .init(open: {}))
        NotificationFeedRow(entry: entries[7], icon: nil, now: NotificationFeedPreviewData.now,
                            isNew: false, isSelected: false, actions: .init())
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding()
    .frame(width: 380)
}
#endif
