import SwiftUI

/// Requested size, hover scale, and indicators. The page pins its preview above this pane
/// (`DockPagePreviewStrip`) so the sample stays visible while the controls scroll.
struct AppearanceSettingsPane: View {
    var edge: DockEdge = .bottom
    @Binding var iconSize: Double
    @Binding var magnification: Double
    @Binding var itemSpacing: Double
    @Binding var cornerRadius: Double
    @Binding var runningIndicatorStyle: DockSettings.RunningIndicatorStyle
    @Binding var iconStyle: DockIconStyle
    @Binding var launcherLineIcons: Bool
    @Binding var lineIconMotion: LineIconMotionPlayback
    @Binding var animateIndicators: Bool
    @Binding var launchAnimation: DockLaunchAnimation

    var overrideContext: SettingsOverrideContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .settingsCornerRadius, footnote: .settingsCornerRadiusHelp) {
                SettingsSliderRow(title: .settingsCornerRadius, unit: .settingsPoints,
                                  value: $cornerRadius, range: 0...100, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "capsule",
                                  defaultValue: DockSettings.defaults.cornerRadius)
                    .settingsOverride(overrideContext, field: .cornerRadius)
            }
            SettingsCard(title: .settingsIconStyle, footnote: .settingsIconStyleHelp) {
                DockIconStylePicker(selection: $iconStyle)
                    .settingsOverride(overrideContext, field: .iconStyle)
                // One switch for every glyph. The stored value is a trigger, so a launch trigger
                // can join later as a picker without touching saved settings.
                SettingsToggleRow(title: .settingsLineIconMotion,
                                  isOn: Binding(get: { lineIconMotion.playsOnHover },
                                                set: { lineIconMotion = $0 ? .hover : .off }))
                    .disabled(iconStyle != .line)
                    .settingsOverride(overrideContext, field: .lineIconMotion)
                SettingsToggleRow(title: .settingsLauncherLineIcons, isOn: $launcherLineIcons)
                    .disabled(iconStyle != .line)
                    .settingsOverride(overrideContext, field: .launcherLineIcons)
            }
            SettingsCard(title: .settingsCardIcons, footnote: .settingsAppearanceHelp) {
                SettingsSliderRow(title: .settingsIconSize, unit: .settingsPoints,
                                  value: $iconSize, range: 32...96, step: 1,
                                  minimumSymbol: "square", maximumSymbol: "square.fill",
                                  defaultValue: DockSettings.defaults.iconSize)
                    .settingsOverride(overrideContext, field: .iconSize)
                SettingsSliderRow(title: .settingsMagnification, unit: .settingsMultiplier,
                                  value: $magnification, range: 1...2, step: 0.05,
                                  minimumSymbol: "magnifyingglass", maximumSymbol: "plus.magnifyingglass",
                                  defaultValue: DockSettings.defaults.magnification)
                    .settingsOverride(overrideContext, field: .magnification)
                SettingsSliderRow(title: .settingsItemSpacing, unit: .settingsPoints,
                                  value: $itemSpacing, range: 0...24, step: 1,
                                  minimumSymbol: "arrow.left.and.right", maximumSymbol: "arrow.left.and.right",
                                  defaultValue: DockSettings.defaults.itemSpacing)
                    .settingsOverride(overrideContext, field: .itemSpacing)
            }
            SettingsCard(title: .settingsLaunchAnimation, footnote: .settingsLaunchAnimationHelp) {
                DockLaunchAnimationPicker(edge: edge, selection: $launchAnimation)
                    .settingsOverride(overrideContext, field: .launchAnimation)
            }
            SettingsCard(title: .settingsRunningIndicators, footnote: .settingsRunningIndicatorsHelp) {
                RunningIndicatorPicker(edge: edge, selection: $runningIndicatorStyle, animated: animateIndicators)
                    .settingsOverride(overrideContext, field: .runningIndicatorStyle)
                SettingsToggleRow(title: .settingsAnimateIndicators, isOn: $animateIndicators)
                    .disabled(!runningIndicatorStyle.animates)
                    .settingsOverride(overrideContext, field: .animateIndicators)
            }
        }
    }
}

#if DEBUG
#Preview("Appearance pane") {
    @Previewable @State var iconSize: Double = 48
    @Previewable @State var magnification: Double = 1.4
    @Previewable @State var itemSpacing: Double = 4
    @Previewable @State var cornerRadius: Double = 22
    @Previewable @State var indicator: DockSettings.RunningIndicatorStyle = .stardust
    @Previewable @State var iconStyle: DockIconStyle = .native
    @Previewable @State var launcherLineIcons = true
    @Previewable @State var lineIconMotion: LineIconMotionPlayback = .hover
    @Previewable @State var animate = true
    ScrollView {
        AppearanceSettingsPane(iconSize: $iconSize, magnification: $magnification, itemSpacing: $itemSpacing, cornerRadius: $cornerRadius,
                               runningIndicatorStyle: $indicator, iconStyle: $iconStyle,
                               launcherLineIcons: $launcherLineIcons, lineIconMotion: $lineIconMotion,
                               animateIndicators: $animate,
                               launchAnimation: .constant(DockSettings.defaults.launchAnimation))
            .padding(24)
    }
    .tint(SettingsPage.appearance.tint)
    .frame(width: 560, height: 520)
}
#endif
