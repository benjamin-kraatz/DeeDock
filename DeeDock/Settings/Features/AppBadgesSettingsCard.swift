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
                SettingsStackedRow {
                    Text(.appBadgesPermission).foregroundStyle(.secondary)
                }
                SettingsActionRow {
                    Button(.windowAccessEnable, action: windowAccess.requestAccess)
                    Button(.windowAccessOpenSettings, action: windowAccess.openSystemSettings)
                    Button(.windowAccessCheckAgain, action: windowAccess.refresh)
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
        .padding().frame(width: 620)
}
#endif
