import SwiftUI

/// Background and idle controls save independently, including explicit display overrides.
struct DockFadingSettingsPane: View {
    let source: SettingsValueSource
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .appearanceBackground, footnote: .appearanceBackgroundHelp) {
                SettingsToggleRow(title: .appearanceShowBackground, isOn: source.binding(\.showBackground))
                    .settingsOverride(source.context, field: .showBackground)
            }
            SettingsCard(title: .appearanceIdleFading, footnote: .appearanceIdleHelp) {
                SettingsToggleRow(title: .appearanceFadeWhenIdle, isOn: source.binding(\.fadeWhenIdle))
                    .settingsOverride(source.context, field: .fadeWhenIdle)
                idleControls
            }
            SettingsCard(title: .settingsPreview, footnote: .appearanceAccessibilityHelp) {
                SettingsStackedRow { DockFadingPreview(settings: source.value) }
            }
        }
    }

    private var idleControls: some View {
        VStack(spacing: 0) {
            SettingsMenuRow(title: .appearanceFadeTarget, selection: source.binding(\.fadeTarget)) {
                Text(.appearanceFadeEntireDock).tag(DockSettings.FadeTarget.entireDock)
                Text(.appearanceFadeBackground).tag(DockSettings.FadeTarget.backgroundOnly)
                Text(.appearanceFadeIcons).tag(DockSettings.FadeTarget.iconsOnly)
            }
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .fadeTarget)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .appearanceIdleOpacity, unit: .settingsPercent,
                value: source.binding(\.idleOpacity), range: 0...100, step: 5)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .idleOpacity)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .appearanceIdleDelay, unit: .settingsSeconds,
                value: source.binding(\.idleDelay), range: 0...30, step: 1)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .idleDelay)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .appearanceFadeOutDuration, unit: .settingsSeconds,
                value: source.binding(\.fadeOutDuration), range: 0...2, step: 0.05)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .fadeOutDuration)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .appearanceRestoreDuration, unit: .settingsSeconds,
                value: source.binding(\.restoreDuration), range: 0...0.5, step: 0.05)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .restoreDuration)
        }
    }
}

#if DEBUG
#Preview("Fading controls with display overrides") {
    let profiles = DisplaySettingsPreview.make()
    ScrollView {
        DockFadingSettingsPane(source: SettingsValueSource(store: profiles.defaults,
            context: SettingsOverrideContext(profiles: profiles, id: "display.preview2"))).padding(24)
    }.frame(width: 600, height: 750)
}
#endif
