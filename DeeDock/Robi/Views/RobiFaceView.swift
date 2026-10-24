import SwiftUI

/// Robi's face: a dark pill with two eyes and a small smile.
///
/// Asleep, the eyes are half-closed and still. Awake, they open, follow the pointer and blink now
/// and then. While a model is working and nothing has arrived yet the eyes look around on their
/// own, and the smile grows with a small pop when the answer is complete. With Reduce Motion the
/// face neither bounces, blinks, nor moves its eyes.
struct RobiFaceView: View {
    let eyes: RobiEyes
    let phase: RobiPhase
    /// The smaller face used inside the prompt bar.
    var compact = false
    /// True while a model is answering and no text has arrived yet: the eyes wander.
    var isWaiting = false
    var reduceMotion = false
    /// Counts completed answers so the face pops once per answer and never when Robi closes.
    @State private var answers = 0

    private var size: CGSize { compact ? CGSize(width: 40, height: 26) : CGSize(width: 56, height: 32) }
    private var eyeSize: CGSize { compact ? CGSize(width: 7.5, height: 10) : CGSize(width: 10, height: 13) }
    private var blinking: Bool { eyes.isBlinking && !reduceMotion }
    private var wandering: Bool { isWaiting && phase == .thinking && !reduceMotion }

    private var openness: CGFloat {
        if blinking { return 0.12 }
        return phase == .idle ? 0.28 : 1
    }

    private var smileScale: CGFloat {
        switch phase {
        case .idle: 0.01
        case .answered: 1.4
        default: 1
        }
    }

    var body: some View {
        // The timeline only ticks while the eyes wander; otherwise it renders once per state change.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !wandering)) { context in
            face(pupil: pupil(at: context.date))
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(phase == .awake && !reduceMotion ? 1.06 : 1)
        .keyframeAnimator(initialValue: 1.0, trigger: answers) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.1, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.36, spring: .bouncy)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.55), value: phase)
        .animation(.easeInOut(duration: 0.09), value: eyes.isBlinking)
        .onChange(of: phase) { _, phase in
            if phase == .answered, !reduceMotion { answers += 1 }
        }
    }

    private func face(pupil: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.height * 0.38, style: .continuous)
                .fill(Color(red: 0.17, green: 0.15, blue: 0.24))
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            VStack(spacing: compact ? 1 : 2) {
                HStack(spacing: size.width * 0.2) {
                    RobiEyeView(size: eyeSize, pupil: pupil, openness: openness, blinking: blinking)
                    RobiEyeView(size: eyeSize, pupil: pupil, openness: openness, blinking: blinking)
                }
                RobiSmileShape()
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: compact ? 5 : 6, height: 2.5)
                    .opacity(phase == .idle ? 0 : 1)
                    .scaleEffect(smileScale)
                    // The answered smile overshoots a little before settling: that is the pop.
                    .animation(reduceMotion ? .easeInOut(duration: 0.15)
                               : .spring(response: 0.3, dampingFraction: phase == .answered ? 0.42 : 0.55), value: phase)
            }
            .offset(y: compact ? 1 : 2)
        }
    }

    /// Where the pupils point. Waiting for an answer they trace a slow, uneven loop up and to the
    /// sides, as in the mockup; otherwise they follow the pointer through `eyes`.
    private func pupil(at date: Date) -> CGSize {
        guard wandering else { return reduceMotion ? .zero : eyes.pupil }
        let t = date.timeIntervalSinceReferenceDate * 2.2
        return CGSize(width: cos(t) * 2.2, height: -1.4 + sin(t * 1.7) * 0.6)
    }
}

/// One eye: a white capsule with a dark pupil, squashed vertically to blink or sleep.
struct RobiEyeView: View {
    let size: CGSize
    /// Offset in tenths of the eye's width.
    let pupil: CGSize
    let openness: CGFloat
    /// True mid-blink, so the lid snaps shut instead of easing.
    var blinking = false

    var body: some View {
        ZStack {
            Capsule().fill(Color(white: 0.98))
            Circle()
                .fill(Color(red: 0.12, green: 0.10, blue: 0.18))
                .frame(width: size.width * 0.58, height: size.width * 0.58)
                .offset(x: pupil.width * size.width / 10, y: pupil.height * size.width / 10)
                // Pointer events arrive in steps; a short spring turns them into one glance.
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: pupil)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .scaleEffect(x: 1, y: openness, anchor: .center)
        .animation(blinking ? .easeIn(duration: 0.06) : .spring(response: 0.3, dampingFraction: 0.7), value: openness)
    }
}

/// The small smile under the eyes.
struct RobiSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

#if DEBUG
#Preview("Faces") {
    let eyes = RobiEyes()
    HStack(spacing: 18) {
        RobiFaceView(eyes: eyes, phase: .idle)
        RobiFaceView(eyes: eyes, phase: .awake)
        RobiFaceView(eyes: eyes, phase: .answered)
        RobiFaceView(eyes: eyes, phase: .prompting, compact: true)
        RobiFaceView(eyes: eyes, phase: .thinking, compact: true, isWaiting: true)
    }
    .padding(30)
    .background(.white)
}

#Preview("Faces, Reduce Motion") {
    let eyes = RobiEyes()
    HStack(spacing: 18) {
        RobiFaceView(eyes: eyes, phase: .idle, reduceMotion: true)
        RobiFaceView(eyes: eyes, phase: .awake, reduceMotion: true)
        RobiFaceView(eyes: eyes, phase: .thinking, compact: true, isWaiting: true, reduceMotion: true)
        RobiFaceView(eyes: eyes, phase: .answered, compact: true, reduceMotion: true)
    }
    .padding(30)
    .background(Color(red: 0.21, green: 0.23, blue: 0.26))
}
#endif
