import SwiftUI

/// Robi's face: a dark pill with two eyes and a small smile.
///
/// Asleep, the eyes are half-closed and still. Awake, they open, follow the pointer and blink now
/// and then. While a model is working and nothing has arrived yet the eyes look around on their
/// own, and the smile grows with a small pop when the answer is complete. Pressed, it squashes,
/// squeezes its eyes shut, grimaces and sweats, then shakes it off once let go. Circled by the
/// pointer, it gets dizzy: the pupils spin in opposite directions, the mouth goes round, and the
/// face sways. Hit by a picked region flying in, it is startled: the eyes widen with a pop, the
/// pupils shrink and jump up, the mouth rounds, and the face squashes and hops before it settles.
/// With Reduce Motion the face neither bounces, blinks, wobbles, spins, nor moves its eyes; a
/// press only changes its expression, and a surprise is a gentle widen with the round mouth.
struct RobiFaceView: View {
    let eyes: RobiEyes
    let phase: RobiPhase
    /// The smaller face used inside the prompt bar.
    var compact = false
    /// True while a model is answering and no text has arrived yet: the eyes wander.
    var isWaiting = false
    /// An answer waiting on another window: a dot on the face's corner.
    var badge: RobiParkedBadge?
    var reduceMotion = false
    /// Counts completed answers so the face pops once per answer and never when Robi closes.
    @State private var answers = 0
    @Environment(\.robiFacePressed) private var pressed
    /// The squeezed expression. Outlasts a quick click so the reaction is always seen.
    @State private var squeezed = false
    @State private var pressedAt = Date.distantPast
    /// Counts releases: each one shakes the face and schedules the squeeze to end.
    @State private var releases = 0

    /// The shortest time the squeezed face shows, however brief the click.
    private static let minimumSqueeze: TimeInterval = 0.4

    /// Pressed now, or still showing a squeeze that has just been let go.
    private var isSqueezed: Bool { pressed || squeezed }

    private var size: CGSize { compact ? CGSize(width: 40, height: 26) : CGSize(width: 56, height: 32) }
    private var eyeSize: CGSize { compact ? CGSize(width: 7.5, height: 10) : CGSize(width: 10, height: 13) }
    /// Wide eyes do not blink: a blink mid-surprise would shut what should be staring.
    private var blinking: Bool { eyes.isBlinking && !reduceMotion && eyes.surprised == nil }
    private var wandering: Bool { isWaiting && phase == .thinking && !reduceMotion }
    private var dizzy: RobiDizzy? { reduceMotion ? nil : eyes.dizzy }

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
        // The timeline only ticks while the eyes wander, spin, or stare; otherwise it renders
        // once per state change.
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !wandering && dizzy == nil && eyes.surprised == nil)) { context in
            let spin = dizzy.map { RobiDizzySpin($0, at: context.date) }
            let startle = eyes.surprised.map { RobiSurpriseFrame($0, at: context.date, gentle: reduceMotion) }
            let glance = pupil(at: context.date)
            let stare = startle?.pupil(from: glance) ?? glance
            face(left: spin?.left ?? stare, right: spin?.right ?? stare, spin: spin, startle: startle)
                .rotationEffect(.degrees(spin?.sway ?? 0))
                // The hit from below: flatter and wider for an instant, lifted a little, then back.
                .scaleEffect(x: startle?.scale.width ?? 1, y: startle?.scale.height ?? 1)
                .offset(y: startle?.lift ?? 0)
        }
        .frame(width: size.width, height: size.height)
        // Squashed flat and wide between two fingers.
        .scaleEffect(x: isSqueezed && !reduceMotion ? 1.14 : 1, y: isSqueezed && !reduceMotion ? 0.78 : 1)
        .keyframeAnimator(initialValue: RobiWobble(), trigger: releases) { content, wobble in
            content
                .rotationEffect(reduceMotion ? .zero : wobble.angle)
                .scaleEffect(x: 1, y: reduceMotion ? 1 : wobble.stretch, anchor: .bottom)
        } keyframes: { _ in
            RobiWobble.keyframes()
        }
        .scaleEffect(phase == .awake && !reduceMotion ? 1.06 : 1)
        .keyframeAnimator(initialValue: 1.0, trigger: answers) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.1, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.36, spring: .bouncy)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.55), value: phase)
        .animation(.easeInOut(duration: 0.09), value: eyes.isBlinking)
        .animation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.16, dampingFraction: 0.5), value: isSqueezed)
        .onChange(of: phase) { _, phase in
            if phase == .answered, !reduceMotion { answers += 1 }
        }
        .onChange(of: pressed) { _, pressed in
            if pressed {
                pressedAt = .now
                squeezed = true
            } else {
                releases += 1
            }
        }
        // Lets go of the squeeze once it has shown for `minimumSqueeze`. A new release replaces
        // the pending one, and a press that is still held keeps the face squeezed.
        .task(id: releases) {
            guard releases > 0 else { return }
            let remaining = Self.minimumSqueeze - Date.now.timeIntervalSince(pressedAt)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled, !pressed else { return }
            squeezed = false
        }
    }

    private func face(left: CGSize, right: CGSize, spin: RobiDizzySpin?, startle: RobiSurpriseFrame?) -> some View {
        // The round mouth: dizzy breathes it; startled, it opens with the surprise and closes
        // with it, and the smile comes back by the same amount.
        let gasp = spin == nil ? startle?.mouth ?? 0 : 0
        let round: Double? = spin.map { 0.85 + 0.25 * $0.mouth } ?? startle.map { 0.5 + 0.7 * $0.mouth }
        return ZStack {
            RoundedRectangle(cornerRadius: size.height * 0.38, style: .continuous)
                .fill(Color(red: 0.17, green: 0.15, blue: 0.24))
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            VStack(spacing: compact ? 1 : 2) {
                HStack(spacing: size.width * 0.2) {
                    eye(pupil: left, mirrored: false, scale: startle?.eyeScale ?? 1, pupilScale: startle?.pupilScale ?? 1)
                    eye(pupil: right, mirrored: true, scale: startle?.eyeScale ?? 1, pupilScale: startle?.pupilScale ?? 1)
                }
                ZStack {
                    RobiSmileShape()
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: compact ? 5 : 6, height: 2.5)
                        .opacity(phase == .idle || isSqueezed || spin != nil ? 0 : 1 - gasp)
                        .scaleEffect(smileScale)
                        // The answered smile overshoots a little before settling: that is the pop.
                        .animation(reduceMotion ? .easeInOut(duration: 0.15)
                                   : .spring(response: 0.3, dampingFraction: phase == .answered ? 0.42 : 0.55), value: phase)
                    RobiGrimaceShape()
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: compact ? 7 : 9, height: 2.5)
                        .opacity(isSqueezed ? 1 : 0)
                    // Dizzy or startled: a small round "o".
                    Ellipse()
                        .stroke(.white.opacity(0.9), lineWidth: 1.3)
                        .frame(width: compact ? 3.5 : 4.5, height: compact ? 3.5 : 4.5)
                        .scaleEffect(round ?? 0.3)
                        .opacity(isSqueezed ? 0 : spin != nil ? 1 : gasp)
                }
            }
            .offset(y: compact ? 1 : 2)
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                RobiParkedDot(isWorking: badge.isWorking, reduceMotion: reduceMotion)
                    .offset(x: 2.5, y: 2.5)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.55), value: badge)
        .overlay(alignment: .topTrailing) {
            if isSqueezed && !reduceMotion {
                RobiSweatDropShape()
                    .fill(Color(red: 0.62, green: 0.84, blue: 1))
                    .frame(width: compact ? 3.5 : 4.5, height: compact ? 5 : 6.5)
                    .offset(x: compact ? 1 : 2, y: compact ? -1 : -2)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -3)),
                                            removal: .opacity.combined(with: .offset(y: 4))))
            }
        }
    }

    /// One eye: open as usual, widened by `scale` while startled, or squeezed into a chevron
    /// while the face is pressed.
    private func eye(pupil: CGSize, mirrored: Bool, scale: CGFloat, pupilScale: CGFloat) -> some View {
        ZStack {
            RobiEyeView(size: eyeSize, pupil: pupil, openness: openness, blinking: blinking, pupilScale: pupilScale)
                .opacity(isSqueezed ? 0 : 1)
                .scaleEffect(isSqueezed && !reduceMotion ? 0.3 : scale)
            RobiSquintShape(mirrored: mirrored)
                .stroke(Color(white: 0.98), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: eyeSize.width * 0.62, height: eyeSize.height * 0.62)
                .opacity(isSqueezed ? 1 : 0)
        }
        .frame(width: eyeSize.width, height: eyeSize.height)
    }

    /// Where the pupils point. Waiting for an answer they trace a slow, uneven loop up and to the
    /// sides, as in the mockup; otherwise they follow the pointer through `eyes`.
    private func pupil(at date: Date) -> CGSize {
        guard wandering else { return reduceMotion ? .zero : eyes.pupil }
        let t = date.timeIntervalSinceReferenceDate * 2.2
        return CGSize(width: cos(t) * 2.2, height: -1.4 + sin(t * 1.7) * 0.6)
    }
}

/// Where the dizzy face is at one moment: each pupil's place on its circle, the sway of the
/// whole face, and how open the round mouth is.
///
/// The pupils go round `RobiDizzy.rounds` times, fast at first and slowing down, then drift back
/// to the middle over the last fifth. Pupil offsets are in tenths of an eye width with y pointing
/// down, so a growing angle turns clockwise on screen.
struct RobiDizzySpin {
    let left: CGSize
    let right: CGSize
    /// Degrees.
    let sway: Double
    /// 0…1.
    let mouth: Double

    init(_ dizzy: RobiDizzy, at date: Date) {
        let progress = min(1, max(0, date.timeIntervalSince(dizzy.start) / RobiDizzy.duration))
        let eased = 1 - pow(1 - progress, 2.2)
        let angle = eased * RobiDizzy.rounds * 2 * .pi
        let radius = progress < 0.8 ? 1.0 : (1 - progress) / 0.2
        let direction = dizzy.clockwise ? 1.0 : -1.0
        func pupil(_ turn: Double) -> CGSize {
            CGSize(width: cos(turn - .pi / 2) * 2.4 * radius, height: sin(turn - .pi / 2) * 2.0 * radius)
        }
        left = pupil(angle * direction)
        right = pupil(-angle * direction)
        sway = sin(progress * 5 * .pi) * 6 * (1 - progress)
        mouth = (sin(progress * 7 * .pi) + 1) / 2
    }
}

/// The dot for an answer waiting on another window. It breathes while the answer is still being
/// written and turns solid green once it is ready. It only ticks while it breathes.
struct RobiParkedDot: View {
    let isWorking: Bool
    var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isWorking || reduceMotion)) { context in
            let breath = (sin(context.date.timeIntervalSinceReferenceDate * 3.4) + 1) / 2
            Circle()
                .fill(isWorking ? Color.white : Color(red: 0.36, green: 0.86, blue: 0.52))
                .opacity(isWorking ? (reduceMotion ? 0.8 : 0.45 + 0.55 * breath) : 1)
        }
        .frame(width: 7, height: 7)
        // A ring in the face's colour keeps the dot apart from the tab behind it.
        .background(Circle().fill(Color(red: 0.17, green: 0.15, blue: 0.24)).padding(-1.5))
        .animation(.easeInOut(duration: 0.25), value: isWorking)
        .accessibilityHidden(true)
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
    /// The pupil's size relative to its usual, 1 at rest; a startled eye's pupil shrinks.
    var pupilScale: CGFloat = 1

    var body: some View {
        ZStack {
            Capsule().fill(Color(white: 0.98))
            Circle()
                .fill(Color(red: 0.12, green: 0.10, blue: 0.18))
                .frame(width: size.width * 0.58, height: size.width * 0.58)
                .scaleEffect(pupilScale)
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

#Preview("Squeezed") {
    let eyes = RobiEyes()
    HStack(spacing: 18) {
        RobiFaceView(eyes: eyes, phase: .awake)
        RobiFaceView(eyes: eyes, phase: .thinking, compact: true)
        RobiFaceView(eyes: eyes, phase: .awake, reduceMotion: true)
    }
    .environment(\.robiFacePressed, true)
    .padding(30)
    .background(Color(red: 0.21, green: 0.23, blue: 0.26))
}

#Preview("Answer waiting on another window") {
    let eyes = RobiEyes()
    HStack(spacing: 18) {
        RobiFaceView(eyes: eyes, phase: .idle, badge: RobiParkedBadge(isWorking: true, applicationName: "Xcode"))
        RobiFaceView(eyes: eyes, phase: .awake, badge: RobiParkedBadge(isWorking: false, applicationName: "Xcode"))
    }
    .padding(30)
    .background(Color(red: 0.21, green: 0.23, blue: 0.26))
}

#Preview("Dizzy") {
    let eyes = RobiEyes()
    eyes.dizzy = RobiDizzy(start: .now, clockwise: true)
    return HStack(spacing: 18) {
        RobiFaceView(eyes: eyes, phase: .awake)
        RobiFaceView(eyes: eyes, phase: .prompting, compact: true)
    }
    .padding(30)
    .background(Color(red: 0.21, green: 0.23, blue: 0.26))
}

/// Startles the faces every second and a half, so the whole reaction can be watched settle.
private struct RobiSurprisePreview: View {
    @State private var eyes = RobiEyes()
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 18) {
            RobiFaceView(eyes: eyes, phase: .prompting, compact: true, reduceMotion: reduceMotion)
            RobiFaceView(eyes: eyes, phase: .awake, reduceMotion: reduceMotion)
        }
        .padding(30)
        .background(Color(red: 0.21, green: 0.23, blue: 0.26))
        .task {
            while !Task.isCancelled {
                eyes.surprised = RobiSurprise(start: .now)
                try? await Task.sleep(for: .seconds(RobiSurprise.duration))
                eyes.surprised = nil
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

#Preview("Surprised") { RobiSurprisePreview(reduceMotion: false) }
#Preview("Surprised, Reduce Motion") { RobiSurprisePreview(reduceMotion: true) }

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
