import SwiftUI

/// The settings window: a searchable sidebar of panes beside their controls.
///
/// All edits flow through validated, persist-before-publish state in `DockSettingsStore`;
/// this view only routes bindings and never mutates settings directly.
struct DockSettingsView: View {
    let store: DockSettingsStore
    @State private var selection: SettingsCategory? = .appearance
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            SettingsDetailView(store: store, category: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 540, idealHeight: 620)
    }
}

#if DEBUG
#Preview("Settings") {
    DockSettingsView(store: DockSettingsStore(repository: nil))
}

#Preview("Settings — dark") {
    DockSettingsView(store: DockSettingsStore(repository: nil))
        .preferredColorScheme(.dark)
}
#endif
