import SwiftUI

/// Which apps a dock lists. The choice belongs to the active Dock Mode, so it is saved there
/// rather than in the display profile, and the row says so.
struct AppVisibilitySettingsPane: View {
    let source: SettingsValueSource

    var body: some View {
        SettingsCard(title: .settingsAppVisibility, footnote: .settingsAppVisibilityHelp) {
            SettingsMenuRow(title: .settingsAppVisibility,
                            subtitle: source.activeModeName.map { .dockModesSavedIn(modeName: $0) },
                            selection: source.appVisibilityBinding()) {
                ForEach(DockAppVisibility.allCases, id: \.self) { value in Text(value.title).tag(value) }
            }
            .disabled(!source.modeSettingsAvailable)
            .settingsOverride(source.context, field: .appVisibility)
        }
    }
}

#if DEBUG
#Preview("App visibility") {
    ScrollView {
        AppVisibilitySettingsPane(source: SettingsValueSource(store: DockSettingsStore(repository: nil), context: nil))
            .padding(24)
    }
    .frame(width: 620, height: 240)
}
#endif
