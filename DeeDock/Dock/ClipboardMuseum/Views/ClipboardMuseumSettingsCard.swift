import SwiftUI

/// Clipboard Museum controls: collecting, automatic redaction, the curator, opening, clearing,
/// and recovery.
struct ClipboardMuseumSettingsCard: View {
    let museum: ClipboardMuseumController
    let open: () -> Void

    var body: some View {
        let store = museum.store
        ClipboardMuseumSettingsCardContent(
            captureEnabled: store.captureEnabled,
            redactSecrets: store.redactSecrets,
            curatorEnabled: store.curatorEnabled,
            curatorAvailable: museum.curatorAvailable,
            isEmpty: store.isEmpty,
            requiresReset: store.requiresReset,
            storageFailed: store.storageFailed,
            accessDenied: museum.accessDenied,
            setCaptureEnabled: { museum.setCaptureEnabled($0) },
            setRedactSecrets: { store.setRedactSecrets($0) },
            setCuratorEnabled: { store.setCuratorEnabled($0) },
            open: open,
            clear: { store.clear() },
            reset: { museum.reset() })
    }
}

/// The card's rendering, driven by plain values so each state is previewable.
struct ClipboardMuseumSettingsCardContent: View {
    let captureEnabled: Bool
    let redactSecrets: Bool
    let curatorEnabled: Bool
    /// The curator row is absent, not disabled, when the on-device model is unavailable.
    let curatorAvailable: Bool
    let isEmpty: Bool
    /// True when the stored collection could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    let storageFailed: Bool
    let accessDenied: Bool
    let setCaptureEnabled: (Bool) -> Void
    let setRedactSecrets: (Bool) -> Void
    let setCuratorEnabled: (Bool) -> Void
    let open: () -> Void
    let clear: () -> Void
    let reset: () -> Void

    @State private var confirmsClear = false

    /// Options that shape new captures mean nothing while collecting is off. Open and Clear stay
    /// usable for what is already stored.
    private var optionsDisabled: Bool { requiresReset || !captureEnabled }

    var body: some View {
        SettingsCard(title: .clipboardMuseumTitle, footnote: .clipboardMuseumSettingsHelp) {
            SettingsToggleRow(title: .clipboardMuseumCapture, subtitle: .clipboardMuseumCaptureHelp,
                              isOn: Binding(get: { captureEnabled }, set: setCaptureEnabled))
                .disabled(requiresReset)
            SettingsToggleRow(title: .clipboardMuseumRedactSecrets, subtitle: .clipboardMuseumRedactSecretsHelp,
                              isOn: Binding(get: { redactSecrets }, set: setRedactSecrets))
                .disabled(optionsDisabled)
            if curatorAvailable {
                SettingsToggleRow(title: .clipboardMuseumCurate, subtitle: .clipboardMuseumCurateHelp,
                                  isOn: Binding(get: { curatorEnabled }, set: setCuratorEnabled))
                    .disabled(optionsDisabled)
            }
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.clipboardMuseumPrivacyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if accessDenied, captureEnabled {
                        ClipboardMuseumSettingsNotice(message: .clipboardMuseumAccessDenied)
                    }
                    if storageFailed {
                        ClipboardMuseumSettingsNotice(message: .clipboardMuseumStorageFailed)
                    }
                    if requiresReset {
                        ClipboardMuseumSettingsNotice(message: .clipboardMuseumResetHelp)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .opacity(captureEnabled || requiresReset ? 1 : 0.6)
            }
            SettingsActionRow {
                Button(action: open) { Text(.clipboardMuseumOpen) }
                    .disabled(requiresReset)
                Button(role: .destructive) { confirmsClear = true } label: { Text(.clipboardMuseumClear) }
                    .disabled(requiresReset || isEmpty)
                if requiresReset {
                    Button(role: .destructive, action: reset) { Text(.clipboardMuseumReset) }
                }
            }
        }
        .confirmationDialog(Text(.clipboardMuseumClearConfirm), isPresented: $confirmsClear) {
            Button(role: .destructive, action: clear) { Text(.clipboardMuseumClearConfirm) }
        } message: {
            Text(.clipboardMuseumClearHelp)
        }
    }
}

private struct ClipboardMuseumSettingsNotice: View {
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
#Preview("Off: options disabled") {
    ClipboardMuseumSettingsCardContent(captureEnabled: false, redactSecrets: true, curatorEnabled: true,
                                       curatorAvailable: true, isEmpty: false, requiresReset: false,
                                       storageFailed: false, accessDenied: false,
                                       setCaptureEnabled: { _ in }, setRedactSecrets: { _ in },
                                       setCuratorEnabled: { _ in }, open: {}, clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Collecting, curator, dark") {
    ClipboardMuseumSettingsCardContent(captureEnabled: true, redactSecrets: true, curatorEnabled: true,
                                       curatorAvailable: true, isEmpty: false, requiresReset: false,
                                       storageFailed: false, accessDenied: false,
                                       setCaptureEnabled: { _ in }, setRedactSecrets: { _ in },
                                       setCuratorEnabled: { _ in }, open: {}, clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}

#Preview("No model, access denied") {
    ClipboardMuseumSettingsCardContent(captureEnabled: true, redactSecrets: true, curatorEnabled: true,
                                       curatorAvailable: false, isEmpty: true, requiresReset: false,
                                       storageFailed: false, accessDenied: true,
                                       setCaptureEnabled: { _ in }, setRedactSecrets: { _ in },
                                       setCuratorEnabled: { _ in }, open: {}, clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable collection") {
    ClipboardMuseumSettingsCardContent(captureEnabled: false, redactSecrets: true, curatorEnabled: true,
                                       curatorAvailable: true, isEmpty: true, requiresReset: true,
                                       storageFailed: true, accessDenied: false,
                                       setCaptureEnabled: { _ in }, setRedactSecrets: { _ in },
                                       setCuratorEnabled: { _ in }, open: {}, clear: {}, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
