import SwiftUI

/// Icon Rust settings: a live preview with the switch, the unused-day threshold, and local
/// timestamp recovery.
///
/// Reads the live store so a clear or a failed write shows immediately. Presentation
/// lives in ``PinWeatherSettingsCardContent`` so previews can show every state without
/// seeding persistence.
struct PinWeatherSettingsCard: View {
    let weather: PinWeatherStore

    var body: some View {
        PinWeatherSettingsCardContent(
            enabled: weather.enabled,
            unusedDays: weather.unusedDays,
            isEmpty: weather.isEmpty,
            requiresReset: weather.requiresReset,
            storageFailed: weather.storageFailed,
            setEnabled: { weather.setEnabled($0) },
            setUnusedDays: { weather.setUnusedDays($0) },
            clear: { weather.clearTimestamps() },
            reset: { weather.reset() }
        )
    }
}

/// The page's rendering, driven by plain values so each state is previewable.
struct PinWeatherSettingsCardContent: View {
    let enabled: Bool
    let unusedDays: Int
    let isEmpty: Bool
    /// True when stored bytes could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    let storageFailed: Bool
    let setEnabled: (Bool) -> Void
    let setUnusedDays: (Int) -> Void
    let clear: () -> Void
    let reset: () -> Void

    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            PinWeatherShowcase(enabled: enabled, frozen: requiresReset, unusedDays: unusedDays,
                               setEnabled: setEnabled)
            PinWeatherThresholdCard(unusedDays: unusedDays, setUnusedDays: setUnusedDays)
                .disabled(requiresReset || !enabled)
            SettingsCard(footnote: .pinWeatherSettingsHelp) {
                SettingsRow(title: .pinWeatherPrivacyTitle, subtitle: .pinWeatherPrivacyNote) {
                    Button(.pinWeatherClear) { confirmsClear = true }
                        .disabled(requiresReset || isEmpty)
                        // The row gives its copy layout priority; keep the button's title whole.
                        .fixedSize()
                }
                if storageFailed || requiresReset {
                    SettingsStackedRow {
                        VStack(alignment: .leading, spacing: 6) {
                            if storageFailed {
                                PinWeatherSettingsNotice(message: .pinWeatherStorageFailed)
                            }
                            if requiresReset {
                                PinWeatherSettingsNotice(message: .pinWeatherResetHelp)
                            }
                        }
                    }
                }
                if requiresReset {
                    SettingsActionRow {
                        Button(.pinWeatherReset, role: .destructive, action: reset)
                    }
                }
            }
        }
        .confirmationDialog(.pinWeatherClear, isPresented: $confirmsClear) {
            Button(.pinWeatherClearConfirm, role: .destructive, action: clear)
        } message: {
            Text(.pinWeatherClearHelp)
        }
    }
}

/// A short warning line inside the card, for a failed write or an unreadable document.
private struct PinWeatherSettingsNotice: View {
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
#Preview("Rust on") {
    ScrollView {
        PinWeatherSettingsCardContent(enabled: true, unusedDays: 30, isEmpty: false,
                                      requiresReset: false, storageFailed: false,
                                      setEnabled: { _ in }, setUnusedDays: { _ in },
                                      clear: {}, reset: {})
            .padding(24)
    }
    .frame(width: SettingsMetrics.columnWidth, height: 760)
}

#Preview("Rust off, no times") {
    ScrollView {
        PinWeatherSettingsCardContent(enabled: false, unusedDays: 14, isEmpty: true,
                                      requiresReset: false, storageFailed: false,
                                      setEnabled: { _ in }, setUnusedDays: { _ in },
                                      clear: {}, reset: {})
            .padding(24)
    }
    .frame(width: SettingsMetrics.columnWidth, height: 760)
}

#Preview("Unreadable data") {
    ScrollView {
        PinWeatherSettingsCardContent(enabled: true, unusedDays: 30, isEmpty: true,
                                      requiresReset: true, storageFailed: true,
                                      setEnabled: { _ in }, setUnusedDays: { _ in },
                                      clear: {}, reset: {})
            .padding(24)
    }
    .frame(width: SettingsMetrics.columnWidth, height: 820)
}

#Preview("Save failed, light") {
    ScrollView {
        PinWeatherSettingsCardContent(enabled: true, unusedDays: 45, isEmpty: false,
                                      requiresReset: false, storageFailed: true,
                                      setEnabled: { _ in }, setUnusedDays: { _ in },
                                      clear: {}, reset: {})
            .padding(24)
    }
    .frame(width: SettingsMetrics.columnWidth, height: 800)
    .preferredColorScheme(.light)
}
#endif
