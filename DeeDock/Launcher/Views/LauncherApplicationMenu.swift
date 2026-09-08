import SwiftUI

/// Shared actions for grid and list results, scoped to the launcher’s source display.
struct LauncherApplicationMenu: View {
    let application: LauncherApplication
    let state: LauncherState
    var searchResult: LauncherSearchResult? = nil
    var isSuggestion = false

    var body: some View {
        Button {
            if let searchResult { state.search.activate(searchResult) }
            else if isSuggestion { state.openSuggested(application) }
            else { state.open(application) }
        } label: {
            Label { Text(.launcherMenuOpen) } icon: { Image(systemName: "arrow.up.forward.app") }
        }
        Button {
            if let searchResult { state.search.activate(searchResult, reveal: true) }
            else { state.showInFinder(application) }
        } label: {
            Label { Text(.applicationMenuShowInFinder) } icon: { Image(systemName: "folder") }
        }
        Divider()
        Button {
            state.togglePin(application)
        } label: {
            Label {
                Text(state.pinnedIDs.contains(application.id) ? .actionUnpin : .actionPin)
            } icon: {
                Image(systemName: state.pinnedIDs.contains(application.id) ? "pin.slash" : "pin")
            }
        }
        Menu {
            ForEach(state.pinDestinations) { display in
                Button {
                    state.dockStore?.copyPin?(
                        .application(application.reference),
                        display.id
                    )
                } label: {
                    Label { Text(verbatim: display.name) } icon: { Image(systemName: "display") }
                }
            }
        } label: {
            Label { Text(.launcherMenuPinOnDisplay) } icon: { Image(systemName: "display") }
        }
        .disabled(state.pinDestinations.isEmpty)
        Divider()
        Button {
            state.createCapsule?(application.reference)
        } label: {
            Label { Text(.launcherMenuCreateCapsule) } icon: { Image(systemName: "capsule.portrait") }
        }
    }
}
