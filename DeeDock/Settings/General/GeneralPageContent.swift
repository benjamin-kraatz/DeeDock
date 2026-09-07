import SwiftUI

/// App-wide preferences. These stay usable even when display configuration cannot be loaded,
/// so nothing here is disabled by an unreadable dock settings file.
struct GeneralPageContent: View {
    let page: SettingsPage
    let context: SettingsContext
    #if DIRECT_DISTRIBUTION
    @Environment(\.appUpdater) private var updater
    #endif

    var body: some View {
        switch page {
        case .about:
            SettingsCard(title: .updatesSectionTitle) {
                SettingsRow(title: .updatesCurrentVersion) {
                    Text(AppVersionInfo.current.settingsValue).monospacedDigit().textSelection(.enabled)
                }
            }
        case .softwareUpdate:
            updates
        case .menuBar:
            MenuBarIconSettingsCard(controller: context.menuBarIcon)
        case .startup:
            let controller = context.loginItems
            LoginItemSettingsCard(status: controller.status, pendingOperation: controller.pendingOperation,
                                  errorMessage: controller.errorMessage,
                                  setEnabled: { controller.setEnabled($0) },
                                  cancelRequest: { controller.cancelRequest() },
                                  refresh: controller.refresh, openSettings: controller.openSystemSettings,
                                  dismissError: controller.dismissError)
                .onAppear { controller.refresh() }
        default:
            EmptyView()
        }
    }

    /// Only a directly distributed build updates itself; elsewhere the page is not offered at all.
    @ViewBuilder private var updates: some View {
        #if DIRECT_DISTRIBUTION
        if let updater {
            UpdateSettingsCard(currentVersion: AppVersionInfo.current.settingsValue,
                               automaticallyChecks: updater.automaticallyChecksForUpdates,
                               automaticallyInstalls: updater.automaticallyInstallsUpdates,
                               allowsAutomaticInstalls: updater.allowsAutomaticUpdates,
                               canCheck: updater.canCheckForUpdates, updateAvailable: updater.updateAvailable,
                               startupFailed: updater.startupFailed, updateInProgress: updater.updateInProgress,
                               setAutomaticallyChecks: updater.setAutomaticallyChecksForUpdates,
                               setAutomaticallyInstalls: updater.setAutomaticallyInstallsUpdates,
                               check: updater.checkForUpdates)
        }
        #endif
    }
}
