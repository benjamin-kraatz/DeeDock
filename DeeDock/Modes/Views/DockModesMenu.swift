import SwiftUI

/// Menu-bar switching stays nonactivating; only opening Settings deliberately activates DeeDock.
struct DockModesMenu: View {
    let coordinator: DockCoordinator
    @Environment(\.openWindow) private var openWindow

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
            if coordinator.profiles.modes.activeMode.mode69PlusEnabled {
                Button(.mode69PlusStop) {
                    _ = coordinator.profiles.modes.setMode69PlusEnabled(
                        false, for: coordinator.profiles.modes.activeMode.id)
                }
            }
            Divider()
            Menu(.focusStart) {
                ForEach(coordinator.profiles.modes.modes) { mode in
                    Button(mode.name) { coordinator.startFocus(mode) }
                }
            }.disabled(!coordinator.canStartFocus)
            Menu(.recipeMenuTitle) {
                ForEach(coordinator.profiles.modes.modes) { mode in
                    Button(mode.name) { coordinator.prepareWorkspace(mode) }
                        .disabled(!mode.hasRecipe)
                }
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
                openWindow.openDockSettings()
            }
        }
    }
}
