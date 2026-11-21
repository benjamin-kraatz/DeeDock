import SwiftUI

/// The list when nothing fits: a quiet tray where the first icon would be, and one line beside it
/// in the open rail.
struct FlixPickEmptyRow: View {
    let state: FlixPickState

    var body: some View {
        HStack(spacing: FlixPickStyle.iconGap) {
            Image(systemName: "tray")
                .font(.system(size: 15))
                .foregroundStyle(FlixStyle.faint)
                .frame(width: FlixPickStyle.iconBox, height: FlixPickStyle.iconBox)
                .accessibilityHidden(true)
            Text(.flixPickEmpty(state.appName))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .flixPickReveal(state.isOpen)
        }
        .padding(.horizontal, FlixPickStyle.rowPadding)
        .frame(height: FlixPickStyle.rowHeight)
    }
}
