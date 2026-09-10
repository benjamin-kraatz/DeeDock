import SwiftUI

/// Dock Sims controls: the opt-in, how strongly pins move, and recovery from a bad document.
///
/// Reads the live store so a failed write or a reset shows immediately. The presentation lives
/// in ``DockSimsSettingsCardContent`` so every state is previewable without touching storage.
struct DockSimsSettingsCard: View {
    let sims: DockSimsStore

    var body: some View {
        DockSimsSettingsCardContent(
            isEnabled: sims.isEnabled,
            intensity: sims.intensity,
            hasPets: sims.hasPets,
            requiresReset: sims.requiresReset,
            storageFailed: sims.storageFailed,
            setEnabled: { sims.setEnabled($0) },
            setIntensity: { sims.setIntensity($0) },
            resetMoods: { sims.resetMoods() },
            reset: { sims.reset() }
        )
    }
}

/// The card's rendering, driven by plain values so each state is previewable and testable.
struct DockSimsSettingsCardContent: View {
    let isEnabled: Bool
    /// Percent, matching the other Features sliders.
    let intensity: Double
    /// True once at least one pin has been fed, cheered, or settled.
    let hasPets: Bool
    /// True when stored bytes could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    let storageFailed: Bool
    let setEnabled: (Bool) -> Void
    let setIntensity: (Double) -> Void
    let resetMoods: () -> Void
    let reset: () -> Void

    @State private var confirmsResetMoods = false

    var body: some View {
        SettingsCard(title: .simsTitle, footnote: .simsSettingsHelp) {
            SettingsToggleRow(title: .simsEnable, subtitle: .simsEnableHelp,
                              isOn: Binding(get: { isEnabled }, set: setEnabled))
                .disabled(requiresReset)
            SettingsSliderRow(title: .simsIntensity, unit: .settingsPercent,
                              value: Binding(get: { intensity }, set: setIntensity),
                              range: DockSimsLimits.intensityRange,
                              step: DockSimsLimits.intensityStep,
                              minimumSymbol: "tortoise", maximumSymbol: "hare",
                              defaultValue: DockSimsLimits.defaultIntensity)
                .disabled(!isEnabled || requiresReset)
            if !isEnabled && !requiresReset {
                SettingsStackedRow {
                    ContentUnavailableView {
                        Label { Text(.simsEmptyTitle) } icon: { Image(systemName: "face.smiling") }
                    } description: {
                        Text(.simsEmptyMessage)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.simsPrivacyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if storageFailed {
                        DockSimsSettingsNotice(message: .simsStorageFailed)
                    }
                    if requiresReset {
                        DockSimsSettingsNotice(message: .simsResetHelp)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            SettingsActionRow {
                Button(.simsResetMoods, role: .destructive) { confirmsResetMoods = true }
                    .disabled(requiresReset || (!isEnabled && !hasPets))
                if requiresReset {
                    Button(.simsReset, role: .destructive, action: reset)
                }
            }
        }
        .confirmationDialog(.simsResetMoods, isPresented: $confirmsResetMoods) {
            Button(.simsResetMoodsConfirm, role: .destructive, action: resetMoods)
        } message: {
            Text(.simsResetMoodsHelp)
        }
    }
}

/// A short warning line inside the card, for a failed write or an unreadable document.
private struct DockSimsSettingsNotice: View {
    let message: LocalizedStringResource

    var body: some View {
        Label { Text(message) } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Enabled with pets") {
    DockSimsSettingsCardContent(isEnabled: true, intensity: 55, hasPets: true,
                                requiresReset: false, storageFailed: false,
                                setEnabled: { _ in }, setIntensity: { _ in },
                                resetMoods: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Disabled, empty") {
    DockSimsSettingsCardContent(isEnabled: false, intensity: 55, hasPets: false,
                                requiresReset: false, storageFailed: false,
                                setEnabled: { _ in }, setIntensity: { _ in },
                                resetMoods: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable document") {
    DockSimsSettingsCardContent(isEnabled: false, intensity: 55, hasPets: false,
                                requiresReset: true, storageFailed: true,
                                setEnabled: { _ in }, setIntensity: { _ in },
                                resetMoods: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Save failed") {
    DockSimsSettingsCardContent(isEnabled: true, intensity: 100, hasPets: true,
                                requiresReset: false, storageFailed: true,
                                setEnabled: { _ in }, setIntensity: { _ in },
                                resetMoods: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
