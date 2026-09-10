import SwiftUI

/// Local History controls: recording, optional pin preview, clearing, and recovery from an unreadable document.
///
/// Reads the live store so the card reflects a clear or a failed write immediately. The
/// presentation lives in ``DockTimelineSettingsCardContent`` so previews can show every state
/// without seeding persistence.
struct DockTimelineSettingsCard: View {
    let history: DockLocalHistoryStore
    /// Opens the dock as a time axis. Omit where no coordinator is available.
    var browse: (() -> Void)?

    var body: some View {
        DockTimelineSettingsCardContent(
            recordingEnabled: history.recordingEnabled,
            replayEnabled: history.replayEnabled,
            isEmpty: history.isEmpty,
            requiresReset: history.requiresReset,
            storageFailed: history.storageFailed,
            setRecordingEnabled: { history.setRecordingEnabled($0) },
            setReplayEnabled: { history.setReplayEnabled($0) },
            clear: { history.clear() },
            reset: { history.reset() },
            browse: browse
        )
    }
}

/// The card's rendering, driven by plain values so each state is previewable and testable.
struct DockTimelineSettingsCardContent: View {
    let recordingEnabled: Bool
    let replayEnabled: Bool
    let isEmpty: Bool
    /// True when stored bytes could not be read; edits stay frozen until an explicit reset.
    let requiresReset: Bool
    let storageFailed: Bool
    let setRecordingEnabled: (Bool) -> Void
    let setReplayEnabled: (Bool) -> Void
    let clear: () -> Void
    let reset: () -> Void
    var browse: (() -> Void)?

    @State private var confirmsClear = false

    var body: some View {
        SettingsCard(title: .timelineTitle, footnote: .timelineSettingsHelp) {
            SettingsToggleRow(title: .timelineRecord, subtitle: .timelineRecordHelp,
                              isOn: Binding(get: { recordingEnabled }, set: setRecordingEnabled))
                .disabled(requiresReset)
            SettingsToggleRow(title: .timelineReplay, subtitle: .timelineReplayHelp,
                              isOn: Binding(get: { replayEnabled }, set: setReplayEnabled))
                .disabled(requiresReset)
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.timelinePrivacyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if storageFailed {
                        DockTimelineSettingsNotice(message: .timelineStorageFailed)
                    }
                    if requiresReset {
                        DockTimelineSettingsNotice(message: .timelineResetHelp)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            SettingsActionRow {
                if let browse {
                    Button(.actionBrowseLocalHistory, action: browse)
                        .disabled(requiresReset)
                }
                Button(.timelineClear, role: .destructive) { confirmsClear = true }
                    .disabled(requiresReset || isEmpty)
                if requiresReset {
                    Button(.timelineReset, role: .destructive, action: reset)
                }
            }
        }
        .confirmationDialog(.timelineClear, isPresented: $confirmsClear) {
            Button(.timelineClearConfirm, role: .destructive, action: clear)
        } message: {
            Text(.timelineClearHelp)
        }
    }
}

/// A short warning line inside the card, for a failed write or an unreadable document.
private struct DockTimelineSettingsNotice: View {
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
#Preview("Recording on with events") {
    DockTimelineSettingsCardContent(recordingEnabled: true, replayEnabled: false, isEmpty: false,
                                    requiresReset: false, storageFailed: false,
                                    setRecordingEnabled: { _ in }, setReplayEnabled: { _ in },
                                    clear: {}, reset: {}, browse: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Recording off, no events") {
    DockTimelineSettingsCardContent(recordingEnabled: false, replayEnabled: false, isEmpty: true,
                                    requiresReset: false, storageFailed: false,
                                    setRecordingEnabled: { _ in }, setReplayEnabled: { _ in },
                                    clear: {}, reset: {}, browse: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Unreadable history") {
    DockTimelineSettingsCardContent(recordingEnabled: true, replayEnabled: false, isEmpty: true,
                                    requiresReset: true, storageFailed: true,
                                    setRecordingEnabled: { _ in }, setReplayEnabled: { _ in },
                                    clear: {}, reset: {}, browse: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Save failed") {
    DockTimelineSettingsCardContent(recordingEnabled: true, replayEnabled: true, isEmpty: false,
                                    requiresReset: false, storageFailed: true,
                                    setRecordingEnabled: { _ in }, setReplayEnabled: { _ in },
                                    clear: {}, reset: {}, browse: nil)
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
