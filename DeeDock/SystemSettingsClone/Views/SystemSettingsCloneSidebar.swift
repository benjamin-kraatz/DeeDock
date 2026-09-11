import SwiftUI

/// Category list plus a row that opens System Settings at its root.
struct SystemSettingsCloneSidebar: View {
    @Binding var selection: SystemSettingsCloneCategory.ID?
    let query: String
    let openRoot: () -> Void

    private var categories: [SystemSettingsCloneCategory] {
        SystemSettingsDeepLinkCatalog.categories.filter { $0.matches(query) }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(categories) { category in
                    SystemSettingsCloneSidebarRow(
                        category: category,
                        isSelected: selection == category.id
                    )
                    .tag(category.id)
                }
            }
            if categories.isEmpty {
                Text(.systemSettingsCloneEmptySearch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            Section {
                Button(action: openRoot) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(.systemSettingsCloneOpenRoot)
                            Text(.systemSettingsCloneOpenRootSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "gear")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Sidebar row with a copper-family tile and the category name.
struct SystemSettingsCloneSidebarRow: View {
    let category: SystemSettingsCloneCategory
    let isSelected: Bool

    var body: some View {
        Label {
            Text(category.title)
        } icon: {
            SystemSettingsCloneIconTile(
                symbolName: category.symbolName,
                colors: SystemSettingsClonePalette.tileColors(for: category.id),
                size: 22
            )
        }
        .padding(.vertical, 3)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Sidebar") {
    SystemSettingsCloneSidebar(selection: .constant(.displays), query: "", openRoot: {})
        .frame(width: 260, height: 640)
}
#endif
