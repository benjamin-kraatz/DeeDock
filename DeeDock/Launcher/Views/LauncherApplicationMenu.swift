import SwiftUI

/// Shared actions for grid and list results, scoped to the launcher’s source display.
struct LauncherApplicationMenu: View {
    let application: LauncherApplication
    let state: LauncherState
    var searchResult: LauncherSearchResult? = nil

    var body: some View {
        Button(.launcherMenuOpen) {
            if let searchResult { state.search.activate(searchResult) }
            else { state.open(application) }
        }
        Button(.applicationMenuShowInFinder) {
            if let searchResult { state.search.activate(searchResult, reveal: true) }
            else { state.showInFinder(application) }
        }
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
