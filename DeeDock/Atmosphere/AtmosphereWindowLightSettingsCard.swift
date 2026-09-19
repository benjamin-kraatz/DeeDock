import SwiftUI

/// Permission requests happen only through the explicit buttons, never on toggle or launch.
struct AtmosphereWindowLightSettingsCard: View {
    @Binding var settings: AtmosphereWindowLightSettings
    @State private var windowAccess = WindowAccessController(service: SystemWindowAccessService())
    @State private var captureAccess = ScreenCaptureAccessController(service: SystemScreenCaptureAccessService())

    var body: some View {
        SettingsCard(title: .atmosphereLightTitle, footnote: .atmosphereLightHelp) {
            SettingsToggleRow(title: .atmosphereLightEnabled, isOn: $settings.enabled)
            Group {
                SettingsMenuRow(title: .atmosphereLightColor, selection: $settings.mode) {
                    ForEach(AtmosphereWindowLightMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                SettingsToggleRow(title: .atmosphereLightGlowing, isOn: $settings.glowing)
                SettingsToggleRow(title: .atmosphereLightRotation, isOn: $settings.rotates)
                SettingsRow(title: .windowAccessTitle,
                            subtitle: windowAccess.status == .enabled ? .windowAccessStatusEnabled : .windowAccessStatusNotEnabled) {
                    if windowAccess.status != .enabled {
                        Button(.atmosphereLightWindowAccess) { windowAccess.requestAccess() }
                        Button(.windowAccessOpenSettings) { windowAccess.openSystemSettings() }
                    }
                }
                if settings.mode.samplesWindow {
                    SettingsRow(title: .screenCaptureAccessTitle,
                                subtitle: captureAccess.status == .enabled ? .screenCaptureAccessStatusEnabled : .screenCaptureAccessStatusNotEnabled) {
                        if captureAccess.status != .enabled {
                            Button(.atmosphereLightCaptureAccess) { captureAccess.requestAccess() }
                            Button(.windowAccessOpenSettings) { captureAccess.openSystemSettings() }
                        }
                    }
                }
            }
            .disabled(!settings.enabled)
        }
        .onAppear { refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    private func refreshAccess() {
        windowAccess.refresh()
        captureAccess.refresh()
    }
}
