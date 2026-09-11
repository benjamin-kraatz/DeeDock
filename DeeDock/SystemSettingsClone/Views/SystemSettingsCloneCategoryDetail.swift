import SwiftUI

/// Hero plus the pane list for one category, or every matching category while searching.
struct SystemSettingsCloneCategoryDetail: View {
    let groups: [SystemSettingsCloneCategory]
    let open: (SystemSettingsClonePane) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { category in
                    categoryBlock(category)
                }
            }
            .frame(maxWidth: SystemSettingsCloneMetrics.columnWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { wash }
    }

    @ViewBuilder
    private func categoryBlock(_ category: SystemSettingsCloneCategory) -> some View {
        let colors = SystemSettingsClonePalette.tileColors(for: category.id)
        VStack(alignment: .leading, spacing: 14) {
            SystemSettingsCloneHero(category: category, colors: colors)
            SystemSettingsClonePaneCard(panes: category.panes, colors: colors, open: open)
        }
    }

    private var wash: some View {
        LinearGradient(
            colors: [
                SystemSettingsClonePalette.terracotta.opacity(colorScheme == .dark ? 0.16 : 0.10),
                .clear,
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

/// Category artwork, title, and a short description of what the group covers.
struct SystemSettingsCloneHero: View {
    let category: SystemSettingsCloneCategory
    let colors: [Color]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SystemSettingsCloneIconTile(symbolName: category.symbolName, colors: colors, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.title2.weight(.semibold))
                Text(category.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SystemSettingsClonePalette.copper.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Grouped pane rows on one material card.
struct SystemSettingsClonePaneCard: View {
    let panes: [SystemSettingsClonePane]
    let colors: [Color]
    let open: (SystemSettingsClonePane) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SystemSettingsCloneMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                if index > 0 {
                    Divider()
                        .padding(.leading, 62)
                        .opacity(colorScheme == .dark ? 0.55 : 0.9)
                }
                SystemSettingsClonePaneRow(pane: pane, colors: colors) {
                    open(pane)
                }
            }
        }
        .background(.background.secondary, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

#if DEBUG
#Preview("Displays category") {
    if let category = SystemSettingsDeepLinkCatalog.category(id: .displays) {
        SystemSettingsCloneCategoryDetail(groups: [category], open: { _ in })
            .frame(width: 720, height: 640)
    }
}

#Preview("Displays — dark") {
    if let category = SystemSettingsDeepLinkCatalog.category(id: .displays) {
        SystemSettingsCloneCategoryDetail(groups: [category], open: { _ in })
            .preferredColorScheme(.dark)
            .frame(width: 720, height: 640)
    }
}
#endif
