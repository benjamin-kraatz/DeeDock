import SwiftUI

/// The small title above an unfolded stack: sender, count, Show Less, and a ✕ that clears the
/// sender's notifications. The ✕ shows while the pointer is over the group.
struct NotificationFeedGroupHeader: View {
    /// The sender's display name from macOS, or the localized "System".
    let sender: String
    let count: Int
    /// The pointer is over the group, which reveals the ✕.
    let showsClear: Bool
    let showLess: () -> Void
    let clear: () -> Void

    @Environment(\.locale) private var locale
    @State private var lessHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: sender)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            NotificationFeedCountCapsule(count: count)
            Spacer(minLength: 4)
            Button(action: showLess) {
                Text(.notificationFeedShowLess)
                    .font(.caption)
                    .foregroundStyle(lessHovered ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(lessHovered ? 0.085 : 0), in: .rect(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { lessHovered = $0 }
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(showsClear ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: showsClear)
            .help(Text(.notificationFeedClearGroup(count)))
            .accessibilityLabel(Text(.notificationFeedClearGroup(count)))
        }
        .frame(height: 22)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: sender + ", " + countText))
    }

    /// "3 notifications" in the view's locale, joined to the sender's name from macOS.
    private var countText: String {
        var resource = LocalizedStringResource.notificationFeedEntryCount(count)
        resource.locale = locale
        return String(localized: resource)
    }
}

#if DEBUG
#Preview("Group header") {
    VStack(spacing: 12) {
        NotificationFeedGroupHeader(sender: "Mail", count: 3, showsClear: true, showLess: {}, clear: {})
        NotificationFeedGroupHeader(sender: "Messages", count: 12, showsClear: false, showLess: {}, clear: {})
            .environment(\.locale, Locale(identifier: "de"))
    }
    .padding()
    .frame(width: 360)
}
#endif
