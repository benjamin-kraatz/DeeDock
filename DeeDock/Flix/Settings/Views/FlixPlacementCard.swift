import SwiftUI

/// "Where it lives": the dock tile, the menu bar item, and the shortcut with its recorder.
///
/// The status row turns orange when the combination could not be registered (another app holds
/// it) or is one Spotlight or a launcher usually owns.
struct FlixPlacementCard: View {
    @Binding var settings: FlixSettings
    let shortcutStatus: FlixShortcutStatus
    let recordingChanged: (Bool) -> Void
    @State private var recorder = FlixShortcutRecorderModel()

    var body: some View {
        SettingsCard(title: .flixSettingsWhereItLives) {
            SettingsToggleRow(title: .flixSettingsDockTile, subtitle: .flixSettingsDockTileHelp, isOn: $settings.showsDockTile)
            SettingsToggleRow(title: .flixSettingsMenuBar, isOn: $settings.showsMenuBarItem)
            SettingsRow(title: .flixShortcutTitle, subtitle: .flixShortcutHelp) {
                HStack(spacing: 8) {
                    FlixShortcutRecorder(combo: settings.shortcut, model: recorder) { settings.shortcut = .default }
                        .disabled(!settings.shortcutEnabled)
                        .opacity(settings.shortcutEnabled ? 1 : 0.5)
                    Toggle(isOn: $settings.shortcutEnabled) { Text(.flixShortcutTitle) }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            if let refusal = recorder.refusal, recorder.isRecording {
                SettingsStatusRow(symbol: "exclamationmark.circle.fill", tint: .orange, message: Text(refusal))
            } else if settings.shortcutEnabled, let message = statusMessage {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, message: Text(message))
            }
        }
        .onAppear {
            recorder.recorded = { settings.shortcut = $0 }
            recorder.recordingChanged = recordingChanged
        }
    }

    private var statusMessage: LocalizedStringResource? {
        if shortcutStatus == .unavailable { return .flixShortcutUnavailable }
        return FlixShortcutConflict.conflict(for: settings.shortcut)?.message
    }
}
