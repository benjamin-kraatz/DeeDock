import SwiftUI

/// The sheet's footer: what will go to the Trash, what stays, and the buttons for the current phase.
///
/// Return and Escape reach the sheet through ``HubAppsUninstaller/handleKeyDown(_:)``, because the Hub
/// offers keys to the tab before the buttons see them.
struct HubUninstallFooter: View {
    let session: AppUninstallSession
    let uninstaller: HubAppsUninstaller

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                let size = AppUninstallFormat.bytes(session.selectedBytes)
                Text(session.isMeasuring ? .hubUninstallMovesAtLeast(size: size) : .hubUninstallMoves(size: size))
                    .monospacedDigit()
                if session.protectedCount > 0 {
                    Text(.hubUninstallStays(session.protectedCount)).foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            buttons
        }
        .padding(EdgeInsets(top: 12, leading: 22, bottom: 14, trailing: 18))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).accessibilityHidden(true)
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
