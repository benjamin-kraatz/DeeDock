import SwiftUI

/// Searchable defaults and device navigation, retaining the pane artwork and native list styling.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSelection?
    @Binding var searchText: String
    let profiles: DisplayProfilesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matches: [SettingsCategory] { SettingsCategory.allCases.filter { $0.matches(searchText) } }
    private func matches(_ profile: DisplayProfile) -> Bool {
        searchText.isEmpty || profile.name.localizedStandardContains(searchText) || !matches.isEmpty
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                if SettingsSelection.generalMatches(searchText) {
                    Label {
                        Text(.settingsGeneral)
                    } icon: {
                        SettingsIconTile(glyph: .symbol("gearshape.fill"), colors: [.gray, .secondary])
                    }
                    .padding(.vertical, 3)
                    .tag(SettingsSelection.general)
                }

                if SettingsSelection.modesMatches(searchText) {
                    Label {
                        Text(.dockModesTitle)
                    } icon: {
                        SettingsIconTile(glyph: .symbol("square.stack.3d.up.fill"), colors: [.indigo, .purple])
                    }
                    .padding(.vertical, 3)
                    .tag(SettingsSelection.modes)
                }
            }
            Section {
                ForEach(matches) { category in
                    SettingsCategoryRow(category: category, isSelected: selection == .defaults(category))
                        .tag(SettingsSelection.defaults(category))
                }
            } header: { Text(.displayDefaults).font(.caption.weight(.semibold)) }
            Section {
                ForEach(profiles.displays) { display in
                    if let profile = profiles.document.profiles[display.id], matches(profile) {
                        DisplayProfileRow(profile: profile, snapshot: display).tag(SettingsSelection.display(display.id))
                    }
                }
            } header: { Text(.displayConnectedGroup).font(.caption.weight(.semibold)) }
            if !profiles.remembered.isEmpty {
                Section {
                    ForEach(profiles.remembered.filter(matches)) { profile in
                        DisplayProfileRow(profile: profile, snapshot: nil).tag(SettingsSelection.display(profile.id))
                    }
                } header: { Text(.displayRememberedGroup).font(.caption.weight(.semibold)) }
            }
            if !SettingsSelection.generalMatches(searchText)
                && !SettingsSelection.modesMatches(searchText)
                && matches.isEmpty
                && !profiles.document.profiles.values.contains(where: matches)
            {
                Text(.settingsNoMatches)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text(.settingsSearchPrompt))
        .toolbar(removing: .sidebarToggle)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: matches)
    }
}
