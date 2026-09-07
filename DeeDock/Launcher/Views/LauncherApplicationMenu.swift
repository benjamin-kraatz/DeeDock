import SwiftUI

/// Shared actions for grid and list results, scoped to the launcher’s source display.
struct LauncherApplicationMenu: View {
    let application: LauncherApplication
    let state: LauncherState

    var body: some View {
        Button(.launcherMenuOpen) { state.open(application) }
        Button(.applicationMenuShowInFinder) { state.showInFinder(application) }
        Divider()
        Button(
            state.pinnedIDs.contains(application.id) ? .actionUnpin : .actionPin
        ) {
            state.togglePin(application)
        }
        Menu {
            ForEach(state.pinDestinations) { display in
                Button {
                    state.dockStore?.copyPin?(
                        .application(application.reference),
                        display.id
                    )
                } label: {
                    Text(verbatim: display.name)
                }
            }
        } label: {
            Text(.launcherMenuPinOnDisplay)
        }
        .disabled(state.pinDestinations.isEmpty)
        Button(.launcherMenuCreateCapsule) {
            state.createCapsule?(application.reference)
        }
    }
}
