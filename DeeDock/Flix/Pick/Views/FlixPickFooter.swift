import SwiftUI

/// The open rail's last line: how to use a row, or a short note when an action could not reach
/// the picker.
struct FlixPickFooter: View {
    let state: FlixPickState

    var body: some View {
        VStack(spacing: 0) {
            FlixHairline()
            Group {
                if let message = state.message {
                    Text(verbatim: message)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                } else {
                    Text(state.kind == .save ? .flixPickHintSave : .flixPickHintOpen)
                        .foregroundStyle(FlixStyle.faint)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .animation(.easeOut(duration: 0.15), value: state.message)
        }
        .frame(height: FlixPickPlacement.footerHeight)
        .flixPickReveal(state.isOpen)
        .accessibilityHidden(!state.isOpen)
    }
}

/// The list when nothing fits: one quiet line where the rows would be.
struct FlixPickEmptyRow: View {
    let state: FlixPickState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 15))
                .foregroundStyle(FlixStyle.faint)
                .frame(width: 30, height: 30)
            Text(.flixPickEmpty(state.appName))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .flixPickReveal(state.isOpen)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }
}
