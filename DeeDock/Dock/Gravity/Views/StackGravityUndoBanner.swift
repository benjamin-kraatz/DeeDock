import SwiftUI

/// Offers to reverse the last gravity snap, with a dismissal that keeps it.
///
/// Presented inside the dock's callout region and, like the error banner, it receives mouse
/// events so both buttons are clickable through the panel's reported regions.
struct StackGravityUndoBanner: View {
    let message: LocalizedStringResource
    /// Available viewport width, after reserving the dock's horizontal margins.
    let maximumWidth: CGFloat
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
            Text(message).font(.caption).lineLimit(2)
            Button(.stackGravityUndo, action: undo)
                .controlSize(.small)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).accessibilityLabel(Text(.stackGravityDismissUndo))
        }
        // A capsule needs more room on the ends than a rounded rectangle or the trailing
        // dismiss glyph rides its curve.
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: maximumWidth)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Snap undo banner") {
    StackGravityUndoBanner(message: .stackGravityUndoMessage(stackName: "Projects"),
                           maximumWidth: 380, undo: {}, dismiss: {})
        .padding(20)
}

#Preview("Snap undo banner — long stack name, dark") {
    StackGravityUndoBanner(message: .stackGravityUndoMessage(stackName: "Screenshots and Scratch Files"),
                           maximumWidth: 260, undo: {}, dismiss: {})
        .padding(20)
        .preferredColorScheme(.dark)
}
#endif
