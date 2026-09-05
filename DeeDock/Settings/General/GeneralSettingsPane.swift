import SwiftUI

/// App-wide preferences remain usable even when display configuration cannot be loaded.
struct GeneralSettingsPane: View {
    let controller: LoginItemController
    #if DIRECT_DISTRIBUTION
    @Environment(\.appUpdater) private var updater
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                LoginItemSettingsCard(status: controller.status, pendingOperation: controller.pendingOperation,
                                      errorMessage: controller.errorMessage,
                                      setEnabled: { controller.setEnabled($0) },
                                      cancelRequest: { controller.cancelRequest() },
                                      refresh: controller.refresh, openSettings: controller.openSystemSettings,
                                      dismissError: controller.dismissError)
                #if DIRECT_DISTRIBUTION
                if let updater {
                    UpdateSettingsCard(automaticallyChecks: updater.automaticallyChecksForUpdates,
                                       canCheck: updater.canCheckForUpdates, updateAvailable: updater.updateAvailable,
                                       startupFailed: updater.startupFailed, updateInProgress: updater.updateInProgress,
                                       setAutomaticallyChecks: updater.setAutomaticallyChecksForUpdates,
                                       check: updater.checkForUpdates)
                }
                #endif
            }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text(.settingsGeneral))
        .onAppear {
            controller.refresh()
        }
    }
}

#if DEBUG
/// Preview composition never creates a Service Management service.
enum LoginItemPreview {
    static func controller() -> LoginItemController { LoginItemController(service: Service()) }

    private final class Service: LoginItemServicing {
        var status: LoginItemStatus { .notRegistered }
        func register() throws {}
        func unregister() async throws {}
        func openSystemSettings() {}
    }
}

enum WindowAccessPreview {
    static func controller(status: WindowAccessStatus = .notEnabled) -> WindowAccessController {
        WindowAccessController(service: Service(status: status))
    }

    private final class Service: WindowAccessServicing {
        let status: WindowAccessStatus
        init(status: WindowAccessStatus) { self.status = status }
        func requestAccess() {}
        func openSystemSettings() {}
    }
}

enum ScreenCaptureAccessPreview {
    static func controller(status: ScreenCaptureAccessStatus = .notEnabled) -> ScreenCaptureAccessController {
        ScreenCaptureAccessController(service: Service(status: status))
    }

    private final class Service: ScreenCaptureAccessServicing {
        let status: ScreenCaptureAccessStatus
        init(status: ScreenCaptureAccessStatus) { self.status = status }
        func requestAccess() {}
        func openSystemSettings() {}
    }
}

#Preview("General") {
    GeneralSettingsPane(controller: LoginItemPreview.controller())
        .frame(width: 560, height: 520)
}
#endif
