import SwiftUI

/// App-wide preferences remain usable even when display configuration cannot be loaded.
struct GeneralSettingsPane: View {
    let controller: LoginItemController

    var body: some View {
        ScrollView {
            LoginItemSettingsCard(status: controller.status, pendingOperation: controller.pendingOperation,
                                  errorMessage: controller.errorMessage,
                                  setEnabled: { controller.setEnabled($0) },
                                  cancelRequest: { controller.cancelRequest() },
                                  refresh: controller.refresh, openSettings: controller.openSystemSettings,
                                  dismissError: controller.dismissError)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text(.settingsGeneral))
        .onAppear { controller.refresh() }
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

#Preview("General") {
    GeneralSettingsPane(controller: LoginItemPreview.controller()).frame(width: 560, height: 420)
}
#endif
