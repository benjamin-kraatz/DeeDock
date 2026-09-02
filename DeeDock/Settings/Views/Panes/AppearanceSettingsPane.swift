import SwiftUI

/// Requested size and hover scale, previewed above the controls that change them.
struct AppearanceSettingsPane: View {
    @Binding var iconSize: Double
    @Binding var magnification: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: .settingsPreview, footnote: .settingsPreviewDisclaimer) {
                DockAppearancePreview(iconSize: iconSize, magnification: magnification)
            }
            SettingsCard(title: .settingsCardIcons, footnote: .settingsAppearanceHelp) {
                SettingsSliderRow(title: .settingsIconSize, unit: .settingsPoints,
                                  value: $iconSize, range: 32...96, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "square.fill")
                SettingsSliderRow(title: .settingsMagnification, unit: .settingsMultiplier,
                                  value: $magnification, range: 1...2, step: 0.05,
                                  minimumSymbol: "magnifyingglass", maximumSymbol: "plus.magnifyingglass")
            }
        }
    }
}

#if DEBUG
#Preview("Appearance pane") {
    @Previewable @State var iconSize: Double = 48
    @Previewable @State var magnification: Double = 1.4
    ScrollView {
        AppearanceSettingsPane(iconSize: $iconSize, magnification: $magnification)
            .padding(24)
    }
    .tint(SettingsCategory.appearance.tint)
    .frame(width: 560, height: 520)
}
#endif
