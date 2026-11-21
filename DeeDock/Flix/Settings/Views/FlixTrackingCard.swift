import SwiftUI

/// "What it tracks".
struct FlixTrackingCard: View {
    @Binding var settings: FlixSettings

    var body: some View {
        SettingsCard(title: .flixSettingsWhatItTracks) {
            SettingsToggleRow(title: .flixSettingsTrackOpened, subtitle: .flixSettingsTrackOpenedHelp,
                              isOn: $settings.tracksOpenedFiles)
            SettingsToggleRow(title: .flixSettingsTrackWatched, subtitle: .flixSettingsTrackWatchedHelp,
                              isOn: $settings.tracksWatchedFolders)
            SettingsToggleRow(title: .flixSettingsTrackFolders, isOn: $settings.tracksFolders)
            SettingsToggleRow(title: .flixSettingsTrackApps, isOn: $settings.tracksApps)
        }
    }
}
