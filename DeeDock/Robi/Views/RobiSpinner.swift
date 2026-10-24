import SwiftUI

/// A small ring that turns while a model works, in whatever colour the surface needs.
///
/// The system indeterminate `ProgressView` ignores `tint` on macOS and draws grey, which disappears
/// on a dark title bar. This ring takes Robi's ink instead. It turns from a `TimelineView`, so no
/// repeat-forever animation can leak into the springs around it, and it stops ticking as soon as
/// it leaves the hierarchy.
struct RobiSpinner: View {
    let color: Color
    var size: CGFloat = 13
    /// What assistive technology reads for the ring. Nil hides it, for when a caption sits beside it.
    var label: LocalizedStringResource?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40)) { context in
            let turns = context.date.timeIntervalSinceReferenceDate / 0.8
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees((turns - turns.rounded(.down)) * 360))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label.map { Text($0) } ?? Text(verbatim: ""))
    }
}

#if DEBUG
#Preview("Spinner on light and dark") {
    HStack(spacing: 24) {
        RobiSpinner(color: Color(red: 0.13, green: 0.12, blue: 0.17).opacity(0.6))
            .padding(16).background(.white)
        RobiSpinner(color: .white.opacity(0.6))
            .padding(16).background(Color(red: 0.21, green: 0.23, blue: 0.26))
    }
    .padding(20)
}
#endif
