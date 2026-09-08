import SwiftUI

/// The portal's controls, grouped by what they act on.
///
/// Left of the divider is the stream — whether frames keep arriving and whether one is held. Right
/// of it is the view — which part of the window is shown and how close. Last come the two actions
/// that leave the portal: keeping the frame as a file, and going to the window itself. Closing is
/// not here; the panel's own close button, Escape, and the context menu already carry it.
struct WindowPortalToolbar: View {
    @Bindable var state: WindowPortalState
    let opaque: Bool
    /// Owned by the panel so the toolbar cannot vanish out from under an open popover.
    @Binding var viewportControls: Bool

    private var held: Bool { state.userPaused || state.frozen }

    var body: some View {
        HStack(spacing: 2) {
            button(held ? .portalResume : .portalPause, symbol: held ? "play.fill" : "pause.fill",
                   help: held ? .portalResume : .portalPause) { state.togglePause?() }
            button(.portalFreeze, symbol: "snowflake", help: .portalFreeze,
                   disabled: state.image == nil || state.frozen || state.needsReselection) { state.freeze?() }
            separator
            button(.portalCrop, symbol: "crop", help: .portalCrop,
                   disabled: state.image == nil) { state.editCrop?() }
            button(.portalZoom, symbol: "plus.magnifyingglass", help: .portalZoom,
                   disabled: state.image == nil || state.needsReselection) { viewportControls.toggle() }
                .popover(isPresented: $viewportControls, arrowEdge: .bottom) {
                    WindowPortalViewportControls(state: state)
                }
            separator
            button(.portalSave, symbol: "square.and.arrow.down", help: .portalSaveHelp,
                   disabled: state.image == nil) { state.saveFrame?() }
            button(.portalJump, symbol: "arrow.up.forward.app", help: .portalJumpHelp) { state.jump?() }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .modifier(PortalChrome(opaque: opaque))
        .accessibilityElement(children: .contain)
    }

    private var separator: some View {
        Rectangle().fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    private func button(_ label: LocalizedStringResource, symbol: String, help: LocalizedStringResource,
                        disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 13))
            .frame(width: 26, height: 22)
            .contentShape(.rect)
            .disabled(disabled)
            .help(Text(help))
    }
}
