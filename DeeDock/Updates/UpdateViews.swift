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
    let currentVersion: String
    let automaticallyChecks: Bool
    let automaticallyInstalls: Bool
    let allowsAutomaticInstalls: Bool
    let canCheck: Bool
    let updateAvailable: Bool
    let startupFailed: Bool
    var updateInProgress: Bool = false
    var setAutomaticallyChecks: (Bool) -> Void = { _ in }
    var setAutomaticallyInstalls: (Bool) -> Void = { _ in }
    var check: () -> Void = {}

    private var automaticInstallationDescription: LocalizedStringResource {
        allowsAutomaticInstalls || startupFailed
            ? .updatesAutomaticInstallationDescription
            : .updatesAutomaticInstallationRequiresChecks
    }

    var body: some View {
        SettingsCard(title: .updatesSectionTitle) {
            SettingsRow(title: .updatesCurrentVersion) {
                Text(currentVersion).monospacedDigit().textSelection(.enabled)
            }
            SettingsRow(title: .updatesAutomatic, subtitle: .updatesAutomaticDescription) {
                Toggle(isOn: Binding(get: { automaticallyChecks }, set: setAutomaticallyChecks)) {
                    Text(.updatesAutomatic)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(startupFailed)
            }
            SettingsRow(title: .updatesAutomaticInstallation,
                        subtitle: automaticInstallationDescription) {
                Toggle(isOn: Binding(get: { automaticallyInstalls }, set: setAutomaticallyInstalls)) {
                    Text(.updatesAutomaticInstallation)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(startupFailed || !allowsAutomaticInstalls)
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
    UpdateSettingsCard(currentVersion: "0.1.3 (9)", automaticallyChecks: true,
                       automaticallyInstalls: true, allowsAutomaticInstalls: true,
                       canCheck: true, updateAvailable: true, startupFailed: false)
        .padding().frame(width: 560)
}

#Preview("Updater unavailable, German") {
    UpdateSettingsCard(currentVersion: "0.1.3 (9)", automaticallyChecks: false,
                       automaticallyInstalls: false, allowsAutomaticInstalls: false,
                       canCheck: false, updateAvailable: false, startupFailed: true)
        .environment(\.locale, Locale(identifier: "de"))
        .padding().frame(width: 560)
}
#endif
