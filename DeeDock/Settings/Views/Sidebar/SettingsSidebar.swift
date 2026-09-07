import SwiftUI

/// Searchable sections and devices, in the order System Settings uses: what the app is, then what
/// the dock is, then the screens it appears on.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?
    @Binding var searchText: String
    let profiles: DisplayProfilesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A section survives the filter when it, or any page it leads to, matches the query.
    private var sections: [SettingsSection] { SettingsSection.fixed.filter { $0.matches(searchText) } }

    /// A display stays listed when its own name matches, or when the query matches a dock page,
    /// since every dock page can be set for that display.
    private func matches(_ profile: DisplayProfile) -> Bool {
        searchText.isEmpty
            || profile.name.localizedStandardContains(searchText)
            || SettingsSection.dock.matches(searchText)
    }

    private var connected: [DisplaySnapshot] {
        profiles.displays.filter { profiles.document.profiles[$0.id].map(matches) ?? false }
    }
    private var remembered: [DisplayProfile] { profiles.remembered.filter(matches) }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(sections) { section in
                    SettingsSectionRow(section: section, isSelected: selection == section)
                        .tag(section)
                }
            }
            if !connected.isEmpty {
                Section {
                    ForEach(connected) { display in
                        if let profile = profiles.document.profiles[display.id] {
                            DisplayProfileRow(profile: profile, snapshot: display)
                                .tag(SettingsSection.display(display.id))
                        }
                    }
                } header: { Text(.displayConnectedGroup).font(.caption.weight(.semibold)) }
            }
            if !remembered.isEmpty {
                Section {
                    ForEach(remembered) { profile in
                        DisplayProfileRow(profile: profile, snapshot: nil)
                            .tag(SettingsSection.display(profile.id))
                    }
                } header: { Text(.displayRememberedGroup).font(.caption.weight(.semibold)) }
            }
            if sections.isEmpty && connected.isEmpty && remembered.isEmpty {
                Text(.settingsNoMatches)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text(.settingsSearchPrompt))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: sections)
    }
}
