import SwiftUI

/// Which apps a dock lists, shared or overridden per display like the other dock settings.
struct AppVisibilitySettingsPane: View {
    let source: SettingsValueSource

    var body: some View {
        SettingsCard(title: .settingsAppVisibility, footnote: .settingsAppVisibilityHelp) {
            SettingsMenuRow(title: .settingsAppVisibility, selection: source.binding(\.appVisibility)) {
                ForEach(DockAppVisibility.allCases, id: \.self) { value in Text(value.title).tag(value) }
            }
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
