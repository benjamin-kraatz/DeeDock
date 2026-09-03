import SwiftUI

/// Background and idle controls save independently, including explicit display overrides.
struct DockFadingSettingsPane: View {
    let source: SettingsValueSource
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(title: .appearanceBackground, footnote: .appearanceBackgroundHelp) {
                Toggle(isOn: source.binding(\.showBackground)) { Text(.appearanceShowBackground) }
                    .padding(14).settingsOverride(source.context, field: .showBackground)
            }
            SettingsCard(title: .appearanceIdleFading, footnote: .appearanceIdleHelp) {
                Toggle(isOn: source.binding(\.fadeWhenIdle)) { Text(.appearanceFadeWhenIdle) }
                    .padding(14).settingsOverride(source.context, field: .fadeWhenIdle)
                idleControls
            }
            SettingsCard(title: .settingsPreview, footnote: .appearanceAccessibilityHelp) {
                DockFadingPreview(settings: source.value)
            }
        }
    }

    private var idleControls: some View {
        VStack(spacing: 0) {
            Picker(selection: source.binding(\.fadeTarget)) {
                Text(.appearanceFadeEntireDock).tag(DockSettings.FadeTarget.entireDock)
                Text(.appearanceFadeBackground).tag(DockSettings.FadeTarget.backgroundOnly)
                Text(.appearanceFadeIcons).tag(DockSettings.FadeTarget.iconsOnly)
            } label: { Text(.appearanceFadeTarget) }
                .padding(14)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .fadeTarget)
            SettingsSliderRow(title: .appearanceIdleOpacity, unit: .settingsPercent,
                value: source.binding(\.idleOpacity), range: 0...100, step: 5)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .idleOpacity)
            SettingsSliderRow(title: .appearanceIdleDelay, unit: .settingsSeconds,
                value: source.binding(\.idleDelay), range: 0...30, step: 1)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .idleDelay)
            SettingsSliderRow(title: .appearanceFadeOutDuration, unit: .settingsSeconds,
                value: source.binding(\.fadeOutDuration), range: 0...2, step: 0.05)
                .disabled(!source.value.fadeWhenIdle || reduceTransparency)
                .settingsOverride(source.context, field: .fadeOutDuration)
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
