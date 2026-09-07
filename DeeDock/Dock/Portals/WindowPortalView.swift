import SwiftUI

/// View-and-jump controls deliberately do not forward clicks into the captured application.
struct WindowPortalView: View {
    let state: WindowPortalState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = state.image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    ContentUnavailableView {
                        Label(state.phase.label, systemImage: "macwindow")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(verbatim: state.sourceName))
            .accessibilityValue(Text(state.phase.label))
            HStack {
                Text(state.phase.label).font(.caption).lineLimit(2)
                Spacer(minLength: 4)
                Button(state.userPaused ? .portalResume : .portalPause,
                       systemImage: state.userPaused ? "play.fill" : "pause.fill") { state.togglePause?() }
                    .labelStyle(.iconOnly)
                Button(.portalJump, systemImage: "arrow.up.forward.app") { state.jump?() }
                    .labelStyle(.iconOnly)
                    .help(Text(.portalJumpHelp))
                Button(.portalClose, systemImage: "xmark") { state.close?() }
                    .labelStyle(.iconOnly)
            }
            if state.jumpFailed { Text(.portalJumpFallback).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(10)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial))
        .contextMenu {
            Button(.portalJump) { state.jump?() }
            Button(state.userPaused ? .portalResume : .portalPause) { state.togglePause?() }
            Divider()
            Button(.portalMoveLeft) { state.move?(-20, 0) }
            Button(.portalMoveRight) { state.move?(20, 0) }
            Button(.portalMoveUp) { state.move?(0, 20) }
            Button(.portalMoveDown) { state.move?(0, -20) }
            Divider()
            Button(.portalClose) { state.close?() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: state.sourceName))
        .accessibilityHint(Text(.portalKeyboardHelp))
        .accessibilityAction(named: Text(.portalJump)) { state.jump?() }
        .accessibilityAction(named: Text(.portalClose)) { state.close?() }
        .accessibilityAction(named: Text(.portalMoveLeft)) { state.move?(-20, 0) }
        .accessibilityAction(named: Text(.portalMoveRight)) { state.move?(20, 0) }
        .accessibilityAction(named: Text(.portalMoveUp)) { state.move?(0, 20) }
        .accessibilityAction(named: Text(.portalMoveDown)) { state.move?(0, -20) }
    }
}

#if DEBUG
#Preview("Paused portal") {
    let state = WindowPortalState(appName: "Preview", source: ApplicationWindowSummary(
        token: ApplicationWindowToken(sessionID: UUID(), id: UUID()), processIdentifier: 0,
        title: "Reference document", frame: nil, isMinimized: false, isMain: false))
    state.phase = .paused
    return WindowPortalView(state: state).frame(width: 360, height: 240)
}
#endif
