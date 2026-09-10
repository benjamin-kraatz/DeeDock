import SwiftUI

/// The Shortcut greenhouse card on the Action Tiles page: the opt-in, the bed, and recovery.
///
/// The greenhouse is off by default, and while it is off this card shows nothing but the toggle,
/// its help, and any storage notice — no plants, soil, or glass. Watering a plant runs the pinned
/// shortcut through the existing Action Tiles runner, ``ActionTilesController/water(_:)``.
///
/// Discovery is what lets a missing shortcut wilt, so the card asks the controller to load its
/// list once the greenhouse is on. ``ActionTilesController/ensureLoaded()`` already no-ops in
/// Xcode previews, so no preview enumerates real shortcuts.
struct ShortcutGreenhouseSettingsCard: View {
    let store: ShortcutGreenhouseStore
    let controller: ActionTilesController

    var body: some View {
        ShortcutGreenhouseSettingsCardContent(
            isEnabled: store.isEnabled,
            requiresReset: store.requiresReset,
            storageFailed: store.storageFailed,
            plants: store.isEnabled ? controller.plants : [],
            setEnabled: { store.setEnabled($0) },
            water: { controller.water($0) },
            reset: { store.reset() }
        )
        .onAppear { loadIfEnabled() }
        .onChange(of: store.isEnabled) { _, enabled in
            if enabled { controller.ensureLoaded() }
        }
    }

    /// Discovery is what wilt needs. Off stays quiet so the greenhouse does not list Shortcuts
    /// until the user turns it on.
    private func loadIfEnabled() {
        guard store.isEnabled else { return }
        controller.ensureLoaded()
    }
}

/// The card's rendering, driven by plain values so every state is previewable without storage.
struct ShortcutGreenhouseSettingsCardContent: View {
    /// The opt-in. When false, no plant chrome is rendered at all.
    let isEnabled: Bool
    /// True when the stored preference could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    /// True when the preference could not be written.
    let storageFailed: Bool
    /// Pinned Action Tiles as plants. Empty while the greenhouse is off.
    let plants: [ShortcutGreenhousePlant]
    let setEnabled: (Bool) -> Void
    /// Runs one plant's shortcut through the Action Tiles runner.
    let water: (UUID) -> Void
    let reset: () -> Void

    var body: some View {
        SettingsCard(title: .greenhouseTitle, footnote: .greenhouseHelp) {
            SettingsToggleRow(title: .greenhouseEnable, subtitle: .greenhouseEnableHelp,
                              isOn: Binding(get: { isEnabled }, set: setEnabled))
                .disabled(requiresReset)
            if isEnabled && !requiresReset {
                SettingsStackedRow {
                    ShortcutGreenhouseView(plants: plants, water: water)
                }
            }
            if storageFailed || requiresReset {
                SettingsStackedRow {
                    VStack(alignment: .leading, spacing: 6) {
                        if storageFailed {
                            ShortcutGreenhouseNotice(message: .greenhouseStorageFailed)
                        }
                        if requiresReset {
                            ShortcutGreenhouseNotice(message: .greenhouseResetHelp)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if requiresReset {
                SettingsActionRow {
                    Button(.greenhouseReset, role: .destructive, action: reset)
                }
            }
        }
    }
}

/// A short warning line inside the card, for a failed write or an unreadable preference.
private struct ShortcutGreenhouseNotice: View {
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
#Preview("Off by default") {
    ShortcutGreenhouseSettingsCardContent(isEnabled: false, requiresReset: false, storageFailed: false,
                                          plants: [], setEnabled: { _ in }, water: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("On with healthy and wilted") {
    ShortcutGreenhouseSettingsCardContent(isEnabled: true, requiresReset: false, storageFailed: false,
                                          plants: ShortcutGreenhousePlant.previewBed,
                                          setEnabled: { _ in }, water: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("On with nothing pinned") {
    ShortcutGreenhouseSettingsCardContent(isEnabled: true, requiresReset: false, storageFailed: false,
                                          plants: [], setEnabled: { _ in }, water: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable preference") {
    ShortcutGreenhouseSettingsCardContent(isEnabled: false, requiresReset: true, storageFailed: true,
                                          plants: [], setEnabled: { _ in }, water: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("On, dark") {
    ShortcutGreenhouseSettingsCardContent(isEnabled: true, requiresReset: false, storageFailed: false,
                                          plants: ShortcutGreenhousePlant.previewBed,
                                          setEnabled: { _ in }, water: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
