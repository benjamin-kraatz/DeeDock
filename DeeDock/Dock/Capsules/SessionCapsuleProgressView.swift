import SwiftUI

/// Waiting state for the two slow capsule steps: window discovery and draft composition.
///
/// Neither step can report real completion — window capture and on-device summarization finish when
/// they finish — so the bar shows a decelerating estimate instead of a fabricated percentage. It
/// eases toward `Self.ceiling` and never reaches the end on its own; the panel replaces this view
/// when the work actually completes. The subtitle rotates every `Self.rotation` seconds so a long
/// wait still looks alive rather than stuck.
struct SessionCapsuleProgressView: View {
    let headline: LocalizedStringResource
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var estimate: Double = 0
    @State private var messageIndex = 0

    /// How long the estimate takes to ease from empty to `ceiling`.
    private static let ramp: TimeInterval = 75
    /// The estimate stops short of full so the bar never claims work that has not finished.
    private static let ceiling: Double = 0.94
    private static let rotation: Duration = .seconds(10)

    /// Index 0 sets expectations once; the rest cycle for as long as the step runs.
    private static let messages: [LocalizedStringResource] = [
        .capsulesProgressPatience,
        .capsulesProgressStillOne,
        .capsulesProgressStillTwo,
        .capsulesProgressStillThree,
        .capsulesProgressStillFour,
        .capsulesProgressStillFive
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(headline).font(.headline)
                Text(Self.messages[messageIndex])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(messageIndex)
            }
            progressBar
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .task { await run() }
    }

    @ViewBuilder private var progressBar: some View {
        Group {
            if reduceMotion {
                // A crawling bar is the motion here; without it an indeterminate bar is honest.
                ProgressView()
            } else {
                ProgressView(value: estimate)
            }
        }
        .progressViewStyle(.linear)
        .frame(maxWidth: 260)
        .accessibilityHidden(true)
    }

    /// Starts the estimate, then advances the subtitle until the step finishes and the view goes away.
    private func run() async {
        if !reduceMotion {
            withAnimation(.easeOut(duration: Self.ramp)) { estimate = Self.ceiling }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.rotation)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                messageIndex = messageIndex + 1 < Self.messages.count ? messageIndex + 1 : 1
            }
        }
    }
}

#if DEBUG
#Preview("Capsule Progress") {
    SessionCapsuleProgressView(headline: .capsulesReadingContext, symbol: "sparkles")
        .frame(width: 420, height: 300)
}
#endif
