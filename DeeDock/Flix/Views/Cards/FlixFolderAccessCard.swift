import SwiftUI

/// Asks, in context, to see new files in protected watched folders.
///
/// Nothing reads these folders until **Allow…** is pressed; that press is what lets macOS show its
/// Files and Folders prompt. Opened files appear without it, from Spotlight.
struct FlixFolderAccessCard: View {
    let folders: [FlixWatchedFolder]
    let allow: (String) -> Void
    let dismiss: () -> Void

    var body: some View {
        FlixCard {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark").foregroundStyle(Color.accentColor)
                Text(.flixAccessCardTitle).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.flixDismiss))
            }
            Text(.flixAccessCardMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(folders.prefix(4)) { folder in
                    FlixCardButton(title: String(localized: .flixAccessAllowFolder(
                        FileManager.default.displayName(atPath: folder.path)))) { allow(folder.path) }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Folder access card") {
    FlixFolderAccessCard(folders: [FlixWatchedFolder(path: "/Users/preview/Downloads"),
                                   FlixWatchedFolder(path: "/Users/preview/Desktop")],
                         allow: { _ in }, dismiss: {})
        .padding().frame(width: 500)
}
#endif
