import SwiftUI

/// Floating table of contents for the canvas.
///
/// The highlight follows scrolling and slides between rows; clicking a row scrolls the
/// canvas there. The footer opens System Settings itself and explains that nothing here
/// changes a value.
struct SystemSettingsCloneSidebar: View {
    let highlighted: SystemSettingsCloneSection?
    /// Dims the highlight while search results replace the canvas.
    let isSearching: Bool
    let jump: (SystemSettingsCloneSection) -> Void
    let openRoot: () -> Void
    @Namespace private var highlightNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(.quickAccess, title: Text(.systemSettingsCloneQuickAccess), symbol: "star.fill", shortcut: nil)
                    Divider()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    ForEach(Array(SystemSettingsDeepLinkCatalog.categories.enumerated()), id: \.element.id) { index, category in
                        row(
                            .category(category.id),
                            title: Text(category.title),
                            symbol: category.symbolName,
                            shortcut: index < 9 ? index + 1 : nil
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, SystemSettingsCloneMetrics.titlebarClearance)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.22), value: highlighted)

            SystemSettingsCloneSidebarFooter(openRoot: openRoot)
        }
        .frame(width: SystemSettingsCloneMetrics.sidebarWidth)
    }

    private func row(
        _ section: SystemSettingsCloneSection,
        title: Text,
        symbol: String,
        shortcut: Int?
    ) -> some View {
        let isHighlighted = highlighted == section && !isSearching
        return SystemSettingsCloneSidebarRow(
            title: title,
            symbolName: symbol,
            tint: section.tint,
            isHighlighted: isHighlighted,
            highlightNamespace: highlightNamespace
        ) {
            jump(section)
        }
        .help(Text(verbatim: shortcut.map { "⌘\($0)" } ?? ""))
    }
}

private struct SystemSettingsCloneSidebarRow: View {
    let title: Text
    let symbolName: String
    let tint: SystemSettingsCloneTint
    let isHighlighted: Bool
    let highlightNamespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SystemSettingsCloneIconTile(symbolName: symbolName, tint: tint, size: 24)
                title
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.accent.opacity(0.18))
                        .matchedGeometryEffect(id: "highlight", in: highlightNamespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// Opens System Settings at its root, with the read-only promise underneath.
private struct SystemSettingsCloneSidebarFooter: View {
    let openRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: openRoot) {
                Label {
                    Text(.systemSettingsCloneOpenRoot)
                } icon: {
                    Image(systemName: "gear")
                }
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help(Text(.systemSettingsCloneOpenRootSubtitle))
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9.5))
                    .padding(.top, 1.5)
                    .accessibilityHidden(true)
                Text(.systemSettingsCloneFooter)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(12)
    }
}

#if DEBUG
#Preview("Sidebar") {
    SystemSettingsCloneSidebar(highlighted: .category(.lookAndFeel), isSearching: false, jump: { _ in }, openRoot: {})
        .frame(height: 680)
}
#endif
