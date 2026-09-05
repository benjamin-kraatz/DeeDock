import SwiftUI

/// A keyboard-accessible factory reset shared by numeric sliders and steppers.
/// Callers control visibility and save through the same path as ordinary edits.
struct SettingsResetButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(.settingsResetSliderDefault, systemImage: "arrow.counterclockwise")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(.settingsResetValue(title: String(localized: title))))
        .help(Text(.settingsResetValueHelp))
    }
}
