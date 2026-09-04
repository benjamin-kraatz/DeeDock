import SwiftUI

/// Waiting state for the two slow capsule steps: window discovery and draft composition.
///
/// Neither step can report real completion — window capture and on-device summarization finish when
/// they finish — so the bar shows a decelerating estimate instead of a fabricated percentage. It
/// eases toward `Self.ceiling` and never reaches the end on its own; the panel replaces this view
/// when the work actually completes. The subtitle rotates every `Self.rotation` seconds so a long
/// wait still looks alive rather than stuck, and the footer keeps the same shape as every other page
/// so the panel does not jump when the work finishes.
struct SessionCapsuleProgressView: View {
    let headline: LocalizedStringResource
    /// Drawn behind the capsule mark to say which step is running.
    let symbol: String
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.capsuleMotion) private var motion
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
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                mark
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
            HStack {
                Spacer(minLength: 0)
                Button(.capsulesCancel, role: .cancel) { cancel() }
                    .controlSize(.large)
            }
            .capsuleFooterBar()
        }
        .task { await run() }
    }

    /// The capsule mark turning inside a soft halo, with the step's own symbol tucked beside it.
    private var mark: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 84, height: 84)
                .scaleEffect(reduceMotion ? 1 : (estimate > 0 ? 1.06 : 0.94))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                           value: estimate > 0)
            CapsuleGlyph(size: 52)
                .phaseAnimator([0.0, 1.0]) { content, phase in
                    content.rotationEffect(.degrees(phase * 12 - 6))
                } animation: { _ in
                    reduceMotion ? nil : .easeInOut(duration: 1.9)
                }
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.accentColor, in: .circle)
                .overlay { Circle().strokeBorder(.background.opacity(0.6), lineWidth: 1) }
                .offset(x: 26, y: 24)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        }
        .frame(height: 92)
        .accessibilityHidden(true)
    }

    /// A drawn track rather than `ProgressView`, so the bar matches the panel's card vocabulary.
    @ViewBuilder private var progressBar: some View {
        if reduceMotion {
            // A crawling bar is the motion here; without it an indeterminate bar is honest.
            ProgressView().progressViewStyle(.linear).frame(maxWidth: 260).accessibilityHidden(true)
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.6))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.7), .accentColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, proxy.size.width * estimate))
                        .overlay(alignment: .trailing) {
                            Circle().fill(.white.opacity(0.85)).frame(width: 4, height: 4)
                                .padding(.trailing, 3)
                        }
                }
            }
            .frame(maxWidth: 260)
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    /// Starts the estimate, then advances the subtitle until the step finishes and the view goes away.
    private func run() async {
        if !reduceMotion {
            withAnimation(.easeOut(duration: Self.ramp)) { estimate = Self.ceiling }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.rotation)
            guard !Task.isCancelled else { return }
            withAnimation(motion.page ?? .easeInOut(duration: 0.35)) {
                messageIndex = messageIndex + 1 < Self.messages.count ? messageIndex + 1 : 1
            }
        }
    }
}

#if DEBUG
#Preview("Capsule Progress") {
    SessionCapsuleProgressView(headline: .capsulesReadingContext, symbol: "sparkles", cancel: {})
        .frame(width: 420, height: 340)
}
#endif
