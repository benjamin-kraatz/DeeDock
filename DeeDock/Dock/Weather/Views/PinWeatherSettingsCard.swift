import SwiftUI

/// Unused-pin weather: enable, unused-day threshold, and local timestamp recovery.
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

/// The card's rendering, driven by plain values so each state is previewable.
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
        SettingsCard(title: .pinWeatherTitle, footnote: .pinWeatherSettingsHelp) {
            SettingsToggleRow(title: .pinWeatherEnabled, subtitle: .pinWeatherEnabledHelp,
                              isOn: Binding(get: { enabled }, set: setEnabled))
                .disabled(requiresReset)
            SettingsSliderRow(title: .pinWeatherUnusedDays, unit: .pinWeatherDays,
                              value: Binding(get: { Double(unusedDays) },
                                             set: { setUnusedDays(Int($0.rounded())) }),
                              range: Double(PinWeatherLimits.unusedDays.lowerBound)...Double(PinWeatherLimits.unusedDays.upperBound),
                              step: 1,
                              defaultValue: Double(PinWeatherLimits.defaultUnusedDays))
                .disabled(requiresReset || !enabled)
            SettingsStackedRow(title: .pinWeatherPreviewTitle, subtitle: .pinWeatherPreviewHelp) {
                PinWeatherRamp(active: enabled && !requiresReset)
            }
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.pinWeatherPrivacyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if storageFailed {
                        PinWeatherSettingsNotice(message: .pinWeatherStorageFailed)
                    }
                    if requiresReset {
                        PinWeatherSettingsNotice(message: .pinWeatherResetHelp)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            SettingsActionRow {
                Button(.pinWeatherClear, role: .destructive) { confirmsClear = true }
                    .disabled(requiresReset || isEmpty)
                if requiresReset {
                    Button(.pinWeatherReset, role: .destructive, action: reset)
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

/// Labeled stages: a pin in use, the first rust after the unused-day setting, then heavy weather.
private struct PinWeatherRamp: View {
    /// Dimmed when weather is off or frozen, so the row matches the disabled controls above it.
    let active: Bool

    private var stops: [(intensity: Double, label: LocalizedStringResource)] {
        [(0, .pinWeatherPreviewClean), (0.32, .pinWeatherPreviewStarts), (1, .pinWeatherPreviewHeavy)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                PinWeatherRampSwatch(intensity: stop.intensity, label: stop.label)
                    .frame(maxWidth: .infinity)
            }
        }
        .opacity(active ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

/// One labeled swatch of the ramp: stand-in artwork under ``PinWeatherLook``.
///
/// Drawn from a gradient rather than a real application icon so the Settings page never touches
/// the workspace or launch services to render a preview.
private struct PinWeatherRampSwatch: View {
    let intensity: Double
    let label: LocalizedStringResource
    private let size: CGFloat = 52

    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(LinearGradient(colors: [
                    Color(red: 0.22, green: 0.62, blue: 0.92),
                    Color(red: 0.10, green: 0.36, blue: 0.78)
                ], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                // Matches the squircle proportion of macOS artwork so the wash lands where it would
                // on a real pin.
                .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
                .modifier(PinWeatherLook(intensity: intensity))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
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
#Preview("Weather on") {
    PinWeatherSettingsCardContent(enabled: true, unusedDays: 30, isEmpty: false,
                                  requiresReset: false, storageFailed: false,
                                  setEnabled: { _ in }, setUnusedDays: { _ in },
                                  clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Weather off, no times") {
    PinWeatherSettingsCardContent(enabled: false, unusedDays: 14, isEmpty: true,
                                  requiresReset: false, storageFailed: false,
                                  setEnabled: { _ in }, setUnusedDays: { _ in },
                                  clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable weather") {
    PinWeatherSettingsCardContent(enabled: true, unusedDays: 30, isEmpty: true,
                                  requiresReset: true, storageFailed: true,
                                  setEnabled: { _ in }, setUnusedDays: { _ in },
                                  clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Save failed, dark") {
    PinWeatherSettingsCardContent(enabled: true, unusedDays: 45, isEmpty: false,
                                  requiresReset: false, storageFailed: true,
                                  setEnabled: { _ in }, setUnusedDays: { _ in },
                                  clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}

#Preview("Reduce Transparency ramp") {
    PinWeatherSettingsCardContent(enabled: true, unusedDays: 30, isEmpty: false,
                                  requiresReset: false, storageFailed: false,
                                  setEnabled: { _ in }, setUnusedDays: { _ in },
                                  clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
