import SwiftUI

/// The sheet's footer: what will go to the Trash, what stays, and the buttons for the current phase.
///
/// Return and Escape reach the sheet through ``HubAppsUninstaller/handleKeyDown(_:)``, because the Hub
/// offers keys to the tab before the buttons see them.
struct HubUninstallFooter: View {
    let session: AppUninstallSession
    let uninstaller: HubAppsUninstaller

    var body: some View {
        HubUninstallFooterBar {
            VStack(alignment: .leading, spacing: 1) {
                let size = AppUninstallFormat.bytes(session.selectedBytes)
                Text(session.isMeasuring ? .hubUninstallMovesAtLeast(size: size) : .hubUninstallMoves(size: size))
                    .monospacedDigit()
                if session.protectedCount > 0 {
                    Text(.hubUninstallStays(session.protectedCount))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            // The summary wraps before a button label truncates (German labels are long).
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Group { buttons }
                .layoutPriority(1)
        }
    }

    @ViewBuilder private var buttons: some View {
        let working = session.phase.isWorking
        Button { uninstaller.end() } label: { Text(.actionCancel) }
            .disabled(working)
        if case .stopped = session.phase {
            Button { session.confirm() } label: { Text(.hubUninstallTryAgain) }
                .buttonStyle(.borderedProminent)
        } else if session.target?.hasSystemExtensions == true {
            Button { session.confirm() } label: { Text(.hubUninstallMoveAnyway) }
                .disabled(working || !session.canConfirm)
        } else {
            Button { session.confirm() } label: { Text(.hubUninstallConfirm) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(working || !session.canConfirm)
        }
    }
}

/// The hairline-topped bar at the bottom of the sheet (mockup `.sh-foot`: padding 12/22/14/18), shared by
/// the review footer and the done view.
struct HubUninstallFooterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(EdgeInsets(top: 12, leading: 22, bottom: 14, trailing: 18))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).accessibilityHidden(true)
            }
    }
}
