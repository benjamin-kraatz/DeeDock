import SwiftUI

/// Inert drag guidance; this never introduces a click target above the dock.
struct DockDragFeedback: View {
    let message: LocalizedStringResource
    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Drag feedback: insertion, unpin, rejection") {
    VStack(spacing: 16) {
        DockDragFeedback(message: .dragPinHere)
        DockDragFeedback(message: .actionUnpin)
        DockDragFeedback(message: .dragRejected)
    }.padding()
}
#endif
