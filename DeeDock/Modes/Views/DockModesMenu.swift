import SwiftUI

/// Menu-bar switching stays nonactivating; only opening Settings deliberately activates DeeDock.
struct DockModesMenu: View {
    let coordinator: DockCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu(.dockModesMenuTitle) {
            ForEach(coordinator.profiles.modes.modes) { mode in
                Button {
                    _ = coordinator.activateMode(mode.id)
                } label: {
                    if mode.id == coordinator.profiles.modes.document.activeModeID {
                        Label(mode.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: mode.name)
                    }
                }
                .disabled(!coordinator.canSwitchModes || mode.id == coordinator.profiles.modes.document.activeModeID)
            }
            Divider()
            if let previous = coordinator.profiles.modes.previousMode {
                Button(.dockModesPrevious(modeName: previous.name)) { _ = coordinator.activatePreviousMode() }
                    .disabled(!coordinator.canSwitchModes)
            } else {
                Button(.dockModesPreviousUnavailable) {}
                    .disabled(true)
            }
            Divider()
            Button(.dockModesManage) {
                coordinator.settingsModesRequest = true
                NSApp.activate()
                openSettings()
            }
        }
    }
}
