import SwiftUI

/// App-wide TCC controls shown beside the display-scoped Peek preferences.
struct PreviewPermissionsSettingsCard: View {
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController

    var body: some View {
        SettingsCard(title: .windowPeekPermissionsTitle, footnote: .windowPeekPermissionsHelp) {
            permissionRows(
                title: .windowAccessTitle,
                status: windowAccess.status.permissionMessage,
                enabled: windowAccess.status == .enabled,
                enableTitle: .windowAccessEnable,
                request: windowAccess.requestAccess,
                refresh: windowAccess.refresh,
                openSettings: windowAccess.openSystemSettings
            )
            permissionRows(
                title: .screenCaptureAccessTitle,
                status: screenCapture.status.permissionMessage,
                enabled: screenCapture.status == .enabled,
                enableTitle: .screenCaptureAccessEnable,
                request: screenCapture.requestAccess,
                refresh: screenCapture.refresh,
                openSettings: screenCapture.openSystemSettings
            )
        }
        .onAppear {
            windowAccess.refresh()
            screenCapture.refresh()
        }
    }

    @ViewBuilder
    private func permissionRows(title: LocalizedStringResource, status: LocalizedStringResource,
                                enabled: Bool, enableTitle: LocalizedStringResource,
                                request: @escaping () -> Void, refresh: @escaping () -> Void,
                                openSettings: @escaping () -> Void) -> some View {
        SettingsStackedRow(title: title) {
            Label {
                Text(status)
            } icon: {
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle.dashed")
            }
            .font(.callout)
            .foregroundStyle(enabled ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
        }
        SettingsActionRow {
            Button(.windowAccessCheckAgain, action: refresh)
            Button(.windowAccessOpenSettings, action: openSettings)
            if !enabled { Button(enableTitle, action: request).buttonStyle(.borderedProminent) }
        }
    }
}

private extension WindowAccessStatus {
    var permissionMessage: LocalizedStringResource {
        switch self {
        case .enabled: .windowAccessStatusEnabled
        case .notEnabled: .windowAccessStatusNotEnabled
        case .unavailable: .windowAccessStatusUnavailable
        }
    }
}

private extension ScreenCaptureAccessStatus {
    var permissionMessage: LocalizedStringResource {
        switch self {
        case .enabled: .screenCaptureAccessStatusEnabled
        case .notEnabled: .screenCaptureAccessStatusNotEnabled
        case .unavailable: .screenCaptureAccessStatusUnavailable
        }
    }
}

#if DEBUG
#Preview("Permissions: both enabled") {
    PreviewPermissionsSettingsCard(windowAccess: WindowAccessPreview.controller(status: .enabled),
                                   screenCapture: ScreenCaptureAccessPreview.controller(status: .enabled))
        .padding().frame(width: 620)
}
#Preview("Permissions: windows only") {
    PreviewPermissionsSettingsCard(windowAccess: WindowAccessPreview.controller(status: .enabled),
                                   screenCapture: ScreenCaptureAccessPreview.controller(status: .notEnabled))
        .padding().frame(width: 620)
}
#Preview("Permissions: thumbnails only") {
    PreviewPermissionsSettingsCard(windowAccess: WindowAccessPreview.controller(status: .notEnabled),
                                   screenCapture: ScreenCaptureAccessPreview.controller(status: .enabled))
        .padding().frame(width: 620)
}
#Preview("Permissions: neither enabled") {
    PreviewPermissionsSettingsCard(windowAccess: WindowAccessPreview.controller(),
                                   screenCapture: ScreenCaptureAccessPreview.controller())
        .padding().frame(width: 620)
}
#endif
