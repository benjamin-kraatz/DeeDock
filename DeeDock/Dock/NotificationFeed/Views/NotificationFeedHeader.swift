import SwiftUI

/// The popover's title row: the bell, how many notifications the feed holds, and Clear All.
struct NotificationFeedHeader: View {
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NotificationFeedGlyph(size: 30, elevated: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(.notificationFeedTitle)
                    .font(.headline)
                Text(.notificationFeedEntryCount(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
            Spacer(minLength: 8)
            if count > 0 {
                Button(action: clear) { Text(.notificationFeedClearAll) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(Text(.notificationFeedClear))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Header") {
    VStack(spacing: 20) {
        NotificationFeedHeader(count: 0, clear: {})
        NotificationFeedHeader(count: 1, clear: {})
        NotificationFeedHeader(count: 42, clear: {})
    }
    .padding()
    .frame(width: 380)
}
#endif
