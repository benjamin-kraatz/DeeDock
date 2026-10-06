import SwiftUI

/// One collected banner: sender, arrival time, and the texts macOS showed.
///
/// Clicking brings the sender forward when its name resolves to a single installed app. Hovering
/// reveals a remove button. Notification text and app names come from macOS and are shown verbatim,
/// never translated.
struct NotificationFeedRow: View {
    let entry: NotificationFeedEntry
    /// The resolved sender's icon, or nil for a system alert or an ambiguous name.
    let icon: NSImage?
    let now: Date
    /// The entry arrived since the feed was last opened.
    let isNew: Bool
    let isSelected: Bool
    let canOpen: Bool
    let open: () -> Void
    let copy: () -> Void
    let remove: () -> Void

    @Environment(\.locale) private var locale
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NotificationFeedSenderIcon(icon: icon, isSystem: entry.appName == nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    sender
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isNew {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
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
        .background { background }
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text(.notificationFeedRemove))
                .padding(6)
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
        .onTapGesture { if canOpen { open() } }
        .contextMenu {
            if canOpen { Button(action: open) { Label { Text(.notificationFeedOpenApp) } icon: { Image(systemName: "arrow.up.forward.app") } } }
            Button(action: copy) { Label { Text(.notificationFeedCopy) } icon: { Image(systemName: "doc.on.doc") } }
            Divider()
            Button(role: .destructive, action: remove) { Label { Text(.notificationFeedRemove) } icon: { Image(systemName: "xmark") } }
        }
        .help(canOpen ? Text(.notificationFeedOpenAppHelp) : Text(verbatim: ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(isNew ? Text(.notificationFeedNewMarker) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityActions {
            if canOpen { Button(action: open) { Text(.notificationFeedOpenApp) } }
            Button(action: copy) { Text(.notificationFeedCopy) }
            Button(action: remove) { Text(.notificationFeedRemove) }
        }
    }

    private var senderName: String {
        entry.appName ?? String(localized: .notificationFeedSystemSender)
    }

    private var sender: Text { Text(verbatim: senderName) }

    /// Relative to the panel's clock rather than the system's, so previews stay fixed.
    private func arrival(_ style: RelativeDateTimeFormatter.UnitsStyle) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = style
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: entry.arrivedAt, relativeTo: max(now, entry.arrivedAt))
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor.opacity(0.18))
                .overlay { shape.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5) }
        } else {
            shape.fill(.primary.opacity(hovered ? 0.08 : 0.04))
        }
    }

    /// Sender, time, and every text in reading order, so VoiceOver reads the banner as one item.
    private var accessibilityLabel: String {
        ([senderName, arrival(.full)] + [entry.title, entry.subtitle, entry.body].compactMap { $0 })
            .joined(separator: ", ")
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
    VStack(spacing: 6) {
        ForEach(Array(NotificationFeedPreviewData.entries.enumerated()), id: \.element.id) { index, entry in
            NotificationFeedRow(entry: entry, icon: nil, now: NotificationFeedPreviewData.now,
                                isNew: index == 0, isSelected: index == 2, canOpen: index != 3,
                                open: {}, copy: {}, remove: {})
        }
    }
    .padding()
    .frame(width: 380)
}
#endif
