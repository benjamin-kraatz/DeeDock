#if DIRECT_DISTRIBUTION
import SwiftUI

extension EnvironmentValues {
    /// Only the direct app composition supplies an updater. Previews default to no service.
    @Entry var appUpdater: AppUpdater? = nil
}

/// Both menus use the same observable availability and pending-update state.
struct CheckForUpdatesButton: View {
    let updater: AppUpdater

    var body: some View {
        Button(action: updater.checkForUpdates) {
            Text(updater.updateAvailable ? .updatesAvailable : updater.updateInProgress ? .updatesShowProgress : .updatesCheck)
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

/// Value-driven settings content can be previewed without networking or real preferences.
struct UpdateSettingsCard: View {
    let automaticallyChecks: Bool
    let canCheck: Bool
    let updateAvailable: Bool
    let startupFailed: Bool
    var updateInProgress: Bool = false
    var setAutomaticallyChecks: (Bool) -> Void = { _ in }
    var check: () -> Void = {}

    var body: some View {
        SettingsCard {
            SettingsRow(title: .updatesAutomatic, subtitle: .updatesAutomaticDescription) {
                Toggle(isOn: Binding(get: { automaticallyChecks }, set: setAutomaticallyChecks)) {
                    Text(.updatesAutomatic)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(startupFailed)
            }
            SettingsActionRow {
                Button(action: check) {
                    Text(updateAvailable ? .updatesAvailable : updateInProgress ? .updatesShowProgress : .updatesCheck)
                }
                .disabled(!canCheck)
            }
            if startupFailed {
                Text(.updatesStartupFailed)
                    .foregroundStyle(.secondary)
                    .padding(SettingsMetrics.rowInset)
            }
        }
    }
}

#Preview("Update available") {
    UpdateSettingsCard(automaticallyChecks: true, canCheck: true, updateAvailable: true, startupFailed: false)
        .padding().frame(width: 560)
}

#Preview("Updater unavailable, German") {
    UpdateSettingsCard(automaticallyChecks: false, canCheck: false, updateAvailable: false, startupFailed: true)
        .environment(\.locale, Locale(identifier: "de"))
        .padding().frame(width: 560)
}
#endif
