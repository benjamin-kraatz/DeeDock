import SwiftUI

/// Searchable sections and devices, in the order System Settings uses: what the app is, what it
/// can do, the screens it appears on, and finally what is on its way out.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?
    @Binding var searchText: String
    let profiles: DisplayProfilesStore
    /// Plugins waiting for approval, counted on the Plugins row. Zero shows no count.
    var pluginsWaiting = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A section survives the filter when it, or any page it leads to, matches the query.
    private func filtered(_ sections: [SettingsSection]) -> [SettingsSection] {
        sections.filter { $0.matches(searchText) }
    }
    private var primary: [SettingsSection] { filtered(SettingsSection.primary) }
    private var features: [SettingsSection] { filtered(SettingsSection.featureSections) }

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

    private var isEmpty: Bool {
        primary.isEmpty && features.isEmpty && connected.isEmpty && remembered.isEmpty
    }

    var body: some View {
        List(selection: $selection) {
            if !primary.isEmpty {
                Section { rows(primary) }
            }
            if !features.isEmpty {
                Section { rows(features) } header: { Text(.settingsFeatures) }
            }
            if !connected.isEmpty {
                Section {
                    ForEach(connected) { display in
                        if let profile = profiles.document.profiles[display.id] {
                            DisplayProfileRow(profile: profile, snapshot: display)
                                .tag(SettingsSection.display(display.id))
                        }
                    }
                } header: { Text(.displayConnectedGroup) }
            }
            if !remembered.isEmpty {
                Section {
                    ForEach(remembered) { profile in
                        DisplayProfileRow(profile: profile, snapshot: nil)
                            .tag(SettingsSection.display(profile.id))
                    }
                } header: { Text(.displayRememberedGroup) }
            }
            if isEmpty {
                Text(.settingsNoMatches)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text(.settingsSearchPrompt))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: primary + features)
    }

    private func rows(_ sections: [SettingsSection]) -> some View {
        ForEach(sections) { section in
            // The tag must stay outermost: wrapped by `.badge`, List no longer finds the row's
            // selection value and clicks on it do nothing.
            SettingsSectionRow(section: section, isSelected: selection == section)
                .badge(section == .plugins ? pluginsWaiting : 0)
                .tag(section)
        }
    }
}
