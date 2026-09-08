import SwiftUI

/// The portal's context menu, grouped the way the portal is used.
///
/// Three sections answer three questions in order: what is shown, what happens to the frame, and
/// what happens to the panel. Moving the panel is a submenu because four directions are one idea,
/// and a flat list of them buried the actions that matter.
struct WindowPortalMenu: View {
    let state: WindowPortalState

    var body: some View {
        Section {
            Button(.portalCrop) { state.editCrop?() }
                .disabled(state.image == nil)
            Button(.portalWholeWindow) { state.applyCrop(NormalizedWindowRegion()) }
            Button(.portalResetCrop) { state.resetZoom() }
                .disabled(state.zoom == 1)
        } header: {
            Text(.portalMenuView)
        }
        Section {
            Button(state.userPaused || state.frozen ? .portalResume : .portalPause) { state.togglePause?() }
            Button(.portalFreeze) { state.freeze?() }
                .disabled(state.image == nil || state.frozen || state.needsReselection)
            Button(.portalSave) { state.saveFrame?() }
                .disabled(state.image == nil)
        } header: {
            Text(.portalMenuFrame)
        }
        Section {
            Button(.portalJump) { state.jump?() }
            Menu {
                Button(.portalMoveLeft) { state.move?(-20, 0) }
                Button(.portalMoveRight) { state.move?(20, 0) }
                Button(.portalMoveUp) { state.move?(0, 20) }
                Button(.portalMoveDown) { state.move?(0, -20) }
            } label: {
                Text(.portalMove)
            }
            Button(.portalClose) { state.close?() }
        } header: {
            Text(.portalMenuWindow)
        }
    }
}
