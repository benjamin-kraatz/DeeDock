import SwiftUI

/// Inert drag guidance; this never introduces a click target above the dock.
struct DockDragFeedback: View {
    let message: LocalizedStringResource
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background {
                if reduceTransparency { Capsule().fill(Color(nsColor: .windowBackgroundColor)) }
                else { Capsule().fill(.regularMaterial) }
            }
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

#Preview("Documents: checking, target, rejection, long name") {
    VStack(spacing: 16) {
        DockDragFeedback(message: .dragCheckingFiles)
        DockDragFeedback(message: .dragOpenIn(appName: "Preview"))
        DockDragFeedback(message: .dragRejected)
        DockDragFeedback(message: .dragOpenIn(appName: "An Application With a Longer Display Name"))
    }.padding()
}
#endif
