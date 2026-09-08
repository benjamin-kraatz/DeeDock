import SwiftUI

/// A timer-only boss portrait. Its health is the existing session's remaining fraction.
struct BossFightGlyph: View {
    let session: FocusSession
    let date: Date
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(.indigo.gradient)
            VStack(spacing: size * 0.035) {
                Image(systemName: session.phase == .paused ? "pause.fill" : "fossil.shell.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(.white).frame(width: geometry.size.width * session.fraction(at: date))
                    }
                }.frame(height: max(2, size * 0.065))
                Text(verbatim: session.timeLabel(at: date))
                    .font(.system(size: size * 0.2, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white).padding(size * 0.12)
        }
        .accessibilityHidden(true)
    }
}

/// A short, local effect that never creates a window or requests keyboard focus.
struct BossFightVictoryGlyph: View {
    let size: CGFloat
    let exposesContent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(.indigo.gradient)
            Image(systemName: "trophy.fill")
                .font(.system(size: size * 0.5)).foregroundStyle(.white)
                .offset(y: lifted && !reduceMotion ? -size * 0.06 : 0)
        }
        .task(id: exposesContent && !reduceMotion) {
            lifted = false
            guard exposesContent && !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.25).repeatCount(2, autoreverses: true)) { lifted = true }
        }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Boss timer, paused") {
    BossFightGlyph(session: FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing",
        duration: 1500, remainingWhenPaused: 750, deadline: nil, phase: .paused),
        date: Date(timeIntervalSince1970: 0), size: 64)
        .frame(width: 64, height: 64).padding()
}
#endif
