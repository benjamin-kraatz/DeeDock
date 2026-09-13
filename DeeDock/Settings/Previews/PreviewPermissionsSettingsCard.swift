import SwiftUI

/// App-wide TCC controls shown beside the display-scoped Peek preferences.
struct PreviewPermissionsSettingsCard: View {
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController

    var body: some View {
        SettingsCard(title: .windowPeekPermissionsTitle, footnote: .windowPeekPermissionsHelp) {
            SettingsPermissionRow(symbol: "macwindow", colors: SettingsPage.windowPeek.tileColors,
                                  title: .windowAccessTitle, status: windowAccess.status.permissionMessage,
                                  state: windowAccess.status.permissionState, enableTitle: .windowAccessEnable,
                                  request: windowAccess.requestAccess, refresh: windowAccess.refresh,
                                  openSettings: windowAccess.openSystemSettings)
            SettingsPermissionRow(symbol: "rectangle.dashed.badge.record", colors: SettingsPage.badges.tileColors,
                                  title: .screenCaptureAccessTitle, status: screenCapture.status.permissionMessage,
                                  state: screenCapture.status.permissionState, enableTitle: .screenCaptureAccessEnable,
                                  request: screenCapture.requestAccess, refresh: screenCapture.refresh,
                                  openSettings: screenCapture.openSystemSettings)
        }
        .onAppear {
            windowAccess.refresh()
            screenCapture.refresh()
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

    var permissionState: SettingsPermissionRow.State {
        switch self {
        case .enabled: .granted
        case .notEnabled: .missing
        case .unavailable: .unavailable
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

    var permissionState: SettingsPermissionRow.State {
        switch self {
        case .enabled: .granted
        case .notEnabled: .missing
        case .unavailable: .unavailable
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
