import SwiftUI

/// App-wide preferences remain usable even when display configuration cannot be loaded.
struct GeneralSettingsPane: View {
    let controller: LoginItemController
    let windowAccess: WindowAccessController

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LoginItemSettingsCard(status: controller.status, pendingOperation: controller.pendingOperation,
                                      errorMessage: controller.errorMessage,
                                      setEnabled: { controller.setEnabled($0) },
                                      cancelRequest: { controller.cancelRequest() },
                                      refresh: controller.refresh, openSettings: controller.openSystemSettings,
                                      dismissError: controller.dismissError)
                WindowAccessSettingsCard(status: windowAccess.status,
                                         requestAccess: windowAccess.requestAccess,
                                         refresh: windowAccess.refresh,
                                         openSettings: windowAccess.openSystemSettings)
            }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text(.settingsGeneral))
        .onAppear {
            controller.refresh()
            windowAccess.refresh()
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
    static func controller() -> WindowAccessController { WindowAccessController(service: Service()) }

    private final class Service: WindowAccessServicing {
        var status: WindowAccessStatus { .notEnabled }
        func requestAccess() {}
        func openSystemSettings() {}
    }
}

#Preview("General") {
    GeneralSettingsPane(controller: LoginItemPreview.controller(), windowAccess: WindowAccessPreview.controller())
        .frame(width: 560, height: 520)
}
#endif
