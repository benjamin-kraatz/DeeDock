import SwiftUI

/// Shared preferences with explicit mode selection, independent of per-display appearance.
struct FocusBreathingSettingsCard: View {
    let store: FocusBreathingStore
    let modes: DockModesStore

    var body: some View {
        SettingsCard(title: .focusBreathingTitle, footnote: .focusBreathingHelp) {
            SettingsToggleRow(title: .focusBreathingEnable,
                              isOn: Binding(get: { store.enabled }, set: store.setEnabled))
            SettingsSliderRow(title: .focusBreathingIntensity, unit: .settingsPercent,
                              value: Binding(get: { store.intensity }, set: store.setIntensity),
                              range: 0...100, step: 1,
                              defaultValue: FocusBreathingStore.defaultIntensity)
                .disabled(!store.enabled)
            SettingsToggleRow(title: .focusBreathingSessions,
                              isOn: Binding(get: { store.usesFocusSessions }, set: store.setUsesFocusSessions))
                .disabled(!store.enabled)
            SettingsStackedRow(title: .focusBreathingModes) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(modes.modes) { mode in
                        Toggle(isOn: Binding(get: { store.modeIDs.contains(mode.id.uuidString) },
                                             set: { store.setMode(mode.id, enabled: $0) })) {
                            Text(verbatim: mode.name)
                        }
                    }
                }
            }
            .disabled(!store.enabled)
            SettingsRow(title: .focusBreathingSystemStatus) {
                Text(store.systemFocusActive ? .focusBreathingFilterOn : .focusBreathingFilterOff)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
