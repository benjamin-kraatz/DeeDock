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
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(.flixAccessCardTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                FlixCloseButton(action: dismiss)
            }
            Text(.flixAccessCardMessage)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // One button per folder; they wrap when the names are long.
            FlixFlow {
                ForEach(folders.prefix(4)) { folder in
                    FlixCardButton(title: String(localized: .flixAccessAllowFolder(
                        FlixFolderNames.displayName(of: folder.path)))) { allow(folder.path) }
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
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
