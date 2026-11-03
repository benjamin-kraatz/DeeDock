import SwiftUI

/// Shared actions for grid and list results, scoped to the launcher’s source display.
///
/// Open and Show in Finder run with the `menu` trigger, so `launcher_result_activated` can tell
/// them from a click on the tile.
struct LauncherApplicationMenu: View {
    let application: LauncherApplication
    let state: LauncherState
    var searchResult: LauncherSearchResult? = nil
    var isSuggestion = false

    var body: some View {
        Button {
            Analytics.performing(.menu) {
                if let searchResult { state.search.activate(searchResult) }
                else if isSuggestion { state.openSuggested(application) }
                else { state.launch(application) }
            }
        } label: {
            Label { Text(.launcherMenuOpen) } icon: { Image(systemName: "arrow.up.forward.app") }
        }
        Button {
            Analytics.performing(.menu) {
                if let searchResult { state.search.activate(searchResult, reveal: true) }
                else { state.reveal(application, suggested: isSuggestion) }
            }
        } label: {
            Label { Text(.applicationMenuShowInFinder) } icon: { Image(systemName: "folder") }
        }
        Divider()
        Button {
            state.toggleFavorite(application)
        } label: {
            Label {
                Text(state.favorites.ids.contains(application.id) ? .launcherRemoveFavorite : .launcherAddFavorite)
            } icon: {
                Image(systemName: state.favorites.ids.contains(application.id) ? "star.slash" : "star")
            }
        }
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
                    state.pin(application, onDisplay: display.id)
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
            state.createCapsule(for: application)
        } label: {
            Label { Text(.launcherMenuCreateCapsule) } icon: { Image(systemName: "capsule.portrait") }
        }
        // Hidden for apps macOS protects (System Integrity Protection) and for DOKK itself.
        if state.uninstall != nil, AppUninstallPathPolicy.allowsApp(application.reference.url) {
            Divider()
            Button(role: .destructive) {
                state.beginUninstall(application)
            } label: {
                Label { Text(.hubUninstallMenu) } icon: { Image(systemName: "trash") }
            }
        }
    }
}
