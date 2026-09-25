import SwiftUI

/// App-badge opt-in, plus the count switch that appears only while badges are on.
///
/// Reuses the app's Accessibility permission flow without prompting during startup or hover.
struct AppBadgesSettingsCard: View {
    @Binding var isOn: Bool
    @Binding var showCounts: Bool
    let windowAccess: WindowAccessController
    let locked: Bool

    var body: some View {
        SettingsCard(title: .appBadgesTitle, footnote: .appBadgesHelp) {
            SettingsToggleRow(title: .appBadgesToggle, isOn: $isOn).disabled(locked)
            if isOn {
                SettingsToggleRow(title: .appBadgeCountsToggle, subtitle: .appBadgeCountsHelp,
                                  isOn: $showCounts)
                    .disabled(locked)
            }
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
    AppBadgesSettingsCard(isOn: .constant(true), showCounts: .constant(false),
                          windowAccess: WindowAccessPreview.controller(), locked: false)
        .padding().frame(width: 640)
}

#Preview("Badges off") {
    AppBadgesSettingsCard(isOn: .constant(false), showCounts: .constant(true),
                          windowAccess: WindowAccessPreview.controller(status: .enabled), locked: false)
        .padding().frame(width: 640)
}

#Preview("Badge numbers") {
    AppBadgesSettingsCard(isOn: .constant(true), showCounts: .constant(true),
                          windowAccess: WindowAccessPreview.controller(status: .enabled), locked: false)
        .padding().frame(width: 640)
}
#endif
