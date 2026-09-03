import SwiftUI

/// Retains the redesigned sidebar, pane previews, cards, and search while adding display scope.
struct DockSettingsView: View {
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore
    @State private var selection: SettingsSelection? = .defaults(.appearance)
    @State private var searchText = ""
    @State private var displayCategory: SettingsCategory = .appearance

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, searchText: $searchText, profiles: profiles)
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
        } detail: {
            switch selection {
            case .defaults(let category):
                SettingsDetailView(store: store, category: category, profileError: profiles.errorMessage)
            case .display(let id):
                SettingsDetailView(store: store, category: displayCategory,
                                   context: SettingsOverrideContext(profiles: profiles, id: id),
                                   profileError: profiles.errorMessage ?? profiles.pinErrors[id], displayCategory: $displayCategory)
                    .id(id)
            case nil:
                SettingsDetailView(store: store, category: nil)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, idealWidth: 820, minHeight: 540, idealHeight: 650)
        .onChange(of: profiles.document.profiles.keys.sorted()) { _, ids in
            if case .display(let id) = selection, !ids.contains(id) { selection = .defaults(.appearance) }
        }
    }
}

#if DEBUG
#Preview("Multiple displays") {
    let profiles = DisplaySettingsPreview.make()
    DockSettingsView(store: profiles.defaults, profiles: profiles)
}
#Preview("Multiple displays — dark") {
    let profiles = DisplaySettingsPreview.make()
    DockSettingsView(store: profiles.defaults, profiles: profiles).preferredColorScheme(.dark)
}
#endif
