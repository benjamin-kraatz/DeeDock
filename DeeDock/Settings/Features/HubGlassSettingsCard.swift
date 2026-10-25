import SwiftUI

/// Settings → DOKK Hub: whether the Hub tints its glass so content stays readable.
///
/// On by default. The value is app-wide (`DockSettings.hubGlassTint`) because only one Hub exists,
/// and an open Hub follows the switch at once. `locked` freezes the switch while the stored
/// preferences are unreadable, leaving the copy readable.
struct HubGlassSettingsCard: View {
    @Binding var isOn: Bool
    var locked: Bool = false

    var body: some View {
        SettingsCard(title: .settingsHubGlassTitle, footnote: .settingsHubGlassTintHelp) {
            SettingsToggleRow(title: .settingsHubGlassTint, subtitle: .settingsHubGlassTintSubtitle, isOn: $isOn)
                .disabled(locked)
        }
    }
}

#if DEBUG
#Preview("Tint on") {
    HubGlassSettingsCard(isOn: .constant(true))
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Tint off, German, dark") {
    HubGlassSettingsCard(isOn: .constant(false))
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
