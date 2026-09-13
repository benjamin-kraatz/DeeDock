import SwiftUI

/// Reuses the app's Accessibility permission flow without prompting during startup or hover.
struct AppBadgesSettingsCard: View {
    @Binding var isOn: Bool
    let windowAccess: WindowAccessController
    let locked: Bool

    var body: some View {
        SettingsCard(title: .appBadgesTitle, footnote: .appBadgesHelp) {
            SettingsToggleRow(title: .appBadgesToggle, isOn: $isOn).disabled(locked)
            if isOn && windowAccess.status != .enabled {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  message: Text(.appBadgesPermission)) {
                    Button(.windowAccessEnable, action: windowAccess.requestAccess)
                        .buttonStyle(.borderedProminent)
                    SettingsMoreMenu {
                        Button(.windowAccessCheckAgain, action: windowAccess.refresh)
                        Button(.windowAccessOpenSettings, action: windowAccess.openSystemSettings)
                    }
                }
            }
        }
        .onAppear { windowAccess.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            windowAccess.refresh()
        }
    }
}

#if DEBUG
#Preview("Badges need access") {
    AppBadgesSettingsCard(isOn: .constant(true), windowAccess: WindowAccessPreview.controller(), locked: false)
        .padding().frame(width: 640)
}
#endif
