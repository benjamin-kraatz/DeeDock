import SwiftUI

/// A thin ring around the close button that empties clockwise as a prompt's 60 seconds run out, and stops while
/// the countdown is paused. It says "this closes itself" without taking a row of its own.
///
/// The session publishes only state changes (running with seconds left, or paused at a fraction); the ring turns
/// each into one linear animation to zero, so nothing ticks while it runs. Decorative: hidden from VoiceOver,
/// which hears the question and its controls instead.
struct AppHealthExpiryRing: View {
    let expiry: AppHealthLabelSession.Expiry
    var lineWidth: CGFloat = 1.5
    @State private var shown: Double = 1

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.quaternary, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: shown)
                .stroke(.tertiary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Trim starts at 3 o'clock; the ring should empty from the top.
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
        .onAppear { apply(expiry) }
        .onChange(of: expiry) { _, next in apply(next) }
    }

    /// Jumps to the current fraction without animation (stopping a running one), then, while running, animates
    /// to zero over the seconds that are left.
    private func apply(_ expiry: AppHealthLabelSession.Expiry) {
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) { shown = expiry.fraction }
        guard let seconds = expiry.secondsLeft, seconds > 0 else { return }
        withAnimation(.linear(duration: seconds)) { shown = 0 }
    }
}

#if DEBUG
#Preview("Expiry ring, paused at fractions") {
    HStack(spacing: 16) {
        ForEach([1.0, 0.75, 0.4, 0.1], id: \.self) { fraction in
            AppHealthExpiryRing(expiry: AppHealthLabelSession.Expiry(fraction: fraction, secondsLeft: nil))
                .frame(width: 22, height: 22)
        }
    }
    .padding()
}
#endif
