import SwiftUI

/// "Labelling paused until tomorrow" with a Resume button, shown after "Pause labelling for today".
struct AppHealthPausedRow: View {
    /// The next local midnight, when prompts come back by themselves.
    let until: Date
    let resume: () -> Void

    var body: some View {
        SettingsStatusRow(symbol: "pause.circle.fill", tint: .secondary, message: Text(.appHealthPausedUntilTomorrow)) {
            Button(.appHealthResume, action: resume)
                .accessibilityHint(Text(.appHealthResumeHint))
        }
        .help(Text(until.formatted(date: .abbreviated, time: .shortened)))
    }
}
