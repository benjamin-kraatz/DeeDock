import SwiftUI

/// A ring with a gap, turning: the marker of the step that is running, and the Run button's
/// glyph while the chain runs. Drawn rather than `ProgressView` so it takes the marker's exact
/// size and colour and sits where the step's number was a moment before.
///
/// It keeps turning with Reduce Motion, as the system's own spinners do: the ring is at most
/// 16 points across, and a still arc would read as stuck.
struct RobiArcSpinner: View {
    var color: Color = .accentColor
    var lineWidth: CGFloat = 2
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            // Explicit, so the turn never inherits the spring of the transition that brought the
            // spinner in and keeps a steady pace from the first frame.
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true } }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Arc spinner") {
    HStack(spacing: 16) {
        RobiArcSpinner().frame(width: 16, height: 16)
        RobiArcSpinner(color: .white, lineWidth: 1.8).frame(width: 14, height: 14)
            .padding(6).background(Color.accentColor, in: Circle())
        RobiArcSpinner(color: .orange, lineWidth: 3).frame(width: 28, height: 28)
    }
    .padding(24)
}
#endif
