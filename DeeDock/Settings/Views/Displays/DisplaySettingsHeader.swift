import SwiftUI

/// Per-display visibility and status; remembered displays remain editable when disconnected.
struct DisplaySettingsHeader: View {
    let context: SettingsOverrideContext
    @Binding var category: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let profile = context.profiles.document.profiles[context.id] {
                Text(verbatim: profile.name).font(.title2.bold())
                SettingsCard {
                    Toggle(isOn: Binding(get: { profile.enabled }, set: { context.profiles.setEnabled($0, for: context.id) })) {
                        Text(.displayShowDock)
                    }
                    .padding(14)
                }
                let display = context.profiles.displays.first { $0.id == context.id }
                if !profile.isPersistent { Text(.displayIdentityWarning).font(.callout).foregroundStyle(.orange) }
                if display?.mirrorSource != nil { Text(.displayMirrorHelp).font(.caption).foregroundStyle(.secondary) }
                if display == nil { Text(.displayDisconnectedHelp).font(.caption).foregroundStyle(.secondary) }
            }
            Picker(selection: $category) {
                ForEach(SettingsCategory.allCases) { category in Text(category.title).tag(category) }
            } label: { Text(.settingsGroupDock) }
            .pickerStyle(.segmented)
        }
    }
}
