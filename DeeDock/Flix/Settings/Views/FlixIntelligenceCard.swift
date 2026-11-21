import SwiftUI

/// "✦ What powers it" and "Helpers": which on-device engines are available and what each helper
/// may do. Every helper degrades on its own: without an engine its surface stays hidden and Flix
/// Files still works.
struct FlixIntelligenceCard: View {
    @Binding var settings: FlixSettings
    let engines: FlixEngineStatus
    let forgetDragMemory: () -> Void

    var body: some View {
        SettingsCard(title: .flixSettingsWhatPowersIt) {
            FlixEngineRow(title: .flixEngineLookout, subtitle: .flixEngineLookoutHelp, state: engines.lookout,
                          readyLabel: { detail in detail.map { .flixEngineOnFolders($0) } ?? .flixEngineOn })
            FlixEngineRow(title: .flixReaderAppleIntelligence, subtitle: .flixEngineAppleIntelligenceHelp,
                          state: engines.appleIntelligence, readyLabel: { _ in .flixEngineAvailable })
            FlixEngineRow(title: .flixEngineRobi,
                          subtitle: engines.robiOnDevice ? .flixEngineRobiHelpOnDevice : .flixEngineRobiHelp,
                          state: engines.robi, readyTint: engines.robiOnDevice ? .green : .accentColor,
                          readyLabel: { _ in engines.robiOnDevice ? .flixEngineRobiOnDevice : .flixEngineRobiClaude })
        }
        SettingsCard {
            SettingsToggleRow(title: .flixSettingsFrontWindow, subtitle: .flixSettingsFrontWindowHelp,
                              isOn: $settings.suggestsForFrontWindow)
            SettingsToggleRow(title: .flixSettingsTilePill, subtitle: .flixSettingsTilePillHelp,
                              isOn: $settings.showsFitsOnTile)
        }
        SettingsCard(title: .flixSettingsHelpers) {
            SettingsToggleRow(title: .flixSettingsCaptions, isOn: $settings.writesCaptions)
            SettingsToggleRow(title: .flixSettingsThreads, isOn: $settings.groupsThreads)
            SettingsToggleRow(title: .flixSettingsFolderSuggestions, isOn: $settings.suggestsFolders)
            SettingsToggleRow(title: .flixSettingsSensitiveGuard, subtitle: .flixSettingsSensitiveGuardHelp,
                              isOn: $settings.guardsSensitiveFiles)
            SettingsToggleRow(title: .flixSettingsHideNoise, subtitle: .flixSettingsHideNoiseHelp, isOn: $settings.hidesNoise)
            SettingsRow(title: .flixSettingsDragMemory, subtitle: .flixSettingsDragMemoryHelp) {
                HStack(spacing: 8) {
                    Button(action: forgetDragMemory) { Text(.flixSettingsForget) }
                        .controlSize(.small)
                    Toggle(isOn: $settings.learnsDragDestinations) { Text(.flixSettingsDragMemory) }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// One engine: what it does and whether this Mac has it.
private struct FlixEngineRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let state: FlixEngineStatus.State
    /// Green for what runs on this Mac; the accent colour for Robi with Claude, as in the mockup.
    var readyTint: Color = .green
    let readyLabel: (Int?) -> LocalizedStringResource

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(tint)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .fixedSize()
                .accessibilityLabel(Text(label))
        }
    }

    private var label: LocalizedStringResource {
        switch state {
        case .ready(let detail): readyLabel(detail)
        case .off: .flixEngineOff
        case .needsSetup: .flixEngineNeedsSetup
        case .unavailable: .flixEngineUnavailable
        }
    }

    private var tint: Color {
        switch state {
        case .ready: readyTint
        case .off, .unavailable: .secondary
        case .needsSetup: .accentColor
        }
    }
}
