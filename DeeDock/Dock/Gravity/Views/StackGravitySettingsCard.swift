import SwiftUI

/// Stack gravity controls: enable, strength, Focus behavior, and recovery from an unreadable
/// document.
///
/// Reads the live store so a failed write or a reset shows immediately. The presentation lives in
/// ``StackGravitySettingsCardContent`` so previews can render every state without persisting.
struct StackGravitySettingsCard: View {
    let store: StackGravityStore

    var body: some View {
        StackGravitySettingsCardContent(
            isEnabled: store.isEnabled,
            strength: store.strength,
            focusBehavior: store.focusBehavior,
            requiresReset: store.requiresReset,
            storageFailed: store.storageFailed,
            setEnabled: { store.setEnabled($0) },
            setStrength: { store.setStrength($0) },
            setFocusBehavior: { store.setFocusBehavior($0) },
            reset: { store.reset() }
        )
    }
}

/// The card's rendering, driven by plain values so each state is previewable and inert.
struct StackGravitySettingsCardContent: View {
    let isEnabled: Bool
    /// Normalized 0...1 pull strength. The slider works in whole percent.
    let strength: Double
    let focusBehavior: StackGravityFocusBehavior
    /// True when stored bytes could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    let storageFailed: Bool
    let setEnabled: (Bool) -> Void
    let setStrength: (Double) -> Void
    let setFocusBehavior: (StackGravityFocusBehavior) -> Void
    let reset: () -> Void

    @State private var confirmsReset = false

    /// Percent facade over the stored fraction, so the slider's 5% step matches what is persisted.
    ///
    /// The getter rounds because scaling a stored fraction such as 0.4 lands a hair off 40, which
    /// would leave the row's reset button enabled at the factory default.
    private var strengthPercent: Binding<Double> {
        Binding(get: { (strength * 100).rounded() }, set: { setStrength($0 / 100) })
    }

    private var focusSelection: Binding<StackGravityFocusBehavior> {
        Binding(get: { focusBehavior }, set: setFocusBehavior)
    }

    private static let focusOptions: [SettingsOption<StackGravityFocusBehavior>] = [
        SettingsOption(value: .keep, title: .stackGravityFocusKeep, symbol: "circle"),
        SettingsOption(value: .mute, title: .stackGravityFocusMute, symbol: "moon"),
        SettingsOption(value: .disable, title: .stackGravityFocusDisable, symbol: "circle.slash")
    ]

    var body: some View {
        SettingsCard(title: .stackGravityTitle, footnote: .stackGravityHelp) {
            SettingsToggleRow(title: .stackGravityToggle,
                              isOn: Binding(get: { isEnabled }, set: setEnabled))
                .disabled(requiresReset)
            SettingsSliderRow(title: .stackGravityStrength, unit: .settingsPercent,
                              value: strengthPercent, range: 0...100, step: 5,
                              minimumSymbol: "minus", maximumSymbol: "plus",
                              defaultValue: 40)
                .disabled(requiresReset)
            SettingsPickerRow(title: .stackGravityFocus, options: Self.focusOptions,
                              selection: focusSelection)
                .disabled(requiresReset)
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 10) {
                    Text(.stackGravityFocusHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StackGravityGuide()
                    if storageFailed {
                        StackGravitySettingsNotice(message: .stackGravityStorageFailed)
                    }
                    if requiresReset {
                        StackGravitySettingsNotice(message: .stackGravityResetHelp)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if requiresReset {
                SettingsActionRow {
                    Button(.stackGravityReset, role: .destructive) { confirmsReset = true }
                }
            }
        }
        .confirmationDialog(.stackGravityReset, isPresented: $confirmsReset) {
            Button(.stackGravityReset, role: .destructive, action: reset)
        } message: {
            Text(.stackGravityResetHelp)
        }
    }
}

/// A short warning line inside the card, for a failed write or an unreadable document.
private struct StackGravitySettingsNotice: View {
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
#Preview("Gravity on at 40%") {
    StackGravitySettingsCardContent(isEnabled: true, strength: 0.4, focusBehavior: .mute,
                                    requiresReset: false, storageFailed: false,
                                    setEnabled: { _ in }, setStrength: { _ in },
                                    setFocusBehavior: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Gravity off") {
    StackGravitySettingsCardContent(isEnabled: false, strength: 0.4, focusBehavior: .keep,
                                    requiresReset: false, storageFailed: false,
                                    setEnabled: { _ in }, setStrength: { _ in },
                                    setFocusBehavior: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable settings") {
    StackGravitySettingsCardContent(isEnabled: true, strength: 0.75, focusBehavior: .disable,
                                    requiresReset: true, storageFailed: true,
                                    setEnabled: { _ in }, setStrength: { _ in },
                                    setFocusBehavior: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Save failed, dark with Reduce Transparency") {
    StackGravitySettingsCardContent(isEnabled: true, strength: 1, focusBehavior: .mute,
                                    requiresReset: false, storageFailed: true,
                                    setEnabled: { _ in }, setStrength: { _ in },
                                    setFocusBehavior: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
