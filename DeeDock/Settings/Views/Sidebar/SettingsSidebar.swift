import SwiftUI

/// Pane navigation with live filtering, ready to hold more grouped entries as settings grow.
struct SettingsSidebar: View {
    @Binding var selection: SettingsCategory?
    @Binding var searchText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matches: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.matches(searchText) }
    }

    var body: some View {
        List(selection: $selection) {
            if matches.isEmpty {
                Text(.settingsNoMatches)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Section {
                    ForEach(matches) { category in
                        SettingsCategoryRow(category: category, isSelected: selection == category)
                            .tag(category)
                    }
                } header: {
                    Text(.settingsGroupDock)
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text(.settingsSearchPrompt))
        // Settings has a fixed two-column shape; a collapse control would only hide navigation.
        .toolbar(removing: .sidebarToggle)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: matches)
    }
}

#if DEBUG
#Preview("Sidebar") {
    @Previewable @State var selection: SettingsCategory? = .appearance
    @Previewable @State var search = ""
    SettingsSidebar(selection: $selection, searchText: $search)
        .frame(width: 215, height: 400)
}
#endif
