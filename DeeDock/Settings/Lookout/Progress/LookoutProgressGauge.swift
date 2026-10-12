import SwiftUI

/// The progress card's ring: onboarding's 120 pt ring (`LookoutProgressRing`) at 56 pt, with the state inside.
///
/// Reading, paused and waiting show the percentage; counting spins an open arc around the spyglass; up to date is a
/// full green ring with a check; stopped is a red arc with an exclamation mark. The arc's colour follows the status
/// chip's dot: the Lookout accent while it works, orange when it waits, green when done, red when stopped.
///
/// Under Reduce Motion the counting arc holds still and the percentage changes without the numeric roll.
struct LookoutProgressGauge: View {
    let progress: LookoutProgressDisplay
    var reduceMotion = HubFilesMotion.reduceMotion
    var size: CGFloat = 56
    var lineWidth: CGFloat = 5

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(HubFilesTheme(scheme).chipHighlight, lineWidth: lineWidth)
            arc
            center
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Arc

    @ViewBuilder private var arc: some View {
        let shown = progress.fraction.map(LookoutProgressFormatting.displayFraction)
        if progress.phase == .counting || shown == nil {
            // Indeterminate: an open arc, turning once every 1.1 s; it holds at 12 o'clock under Reduce Motion.
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 270 : -90))
                .onAppear { startSpinning() }
                .onChange(of: reduceMotion) { startSpinning() }
        } else {
            Circle()
                .trim(from: 0, to: shown ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: shown)
        }
    }

    private func startSpinning() {
        guard !reduceMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { spinning = false }
            return
        }
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spinning = true }
    }

    // MARK: Centre

    @ViewBuilder private var center: some View {
        switch progress.phase {
        case .counting:
            LookoutGlyph(size: size * 0.34)
                .foregroundStyle(color)
        case .upToDate:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(color)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(color)
        case .reading, .paused, .waitingForDrive:
            if let fraction = progress.fraction {
                let shown = LookoutProgressFormatting.displayFraction(fraction)
                Text(verbatim: LookoutProgressFormatting.percent(shown, locale: locale))
                    .font(.system(size: size * 0.215, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: shown))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: shown)
            } else {
                LookoutGlyph(size: size * 0.34)
                    .foregroundStyle(color)
            }
        }
    }

    /// The arc's colour, the status dot's colours.
    private var color: Color {
        switch progress.phase {
        case .counting, .reading: LookoutTheme(scheme).accent
        case .paused, .waitingForDrive: LookoutTheme.paused
        case .upToDate: LookoutTheme.ready
        case .failed: LookoutTheme.failed
        }
    }
}

#if DEBUG
#Preview("Gauges") {
    HStack(spacing: 18) {
        LookoutProgressGauge(progress: .Sample.counting)
        LookoutProgressGauge(progress: .Sample.readingEarly)
        LookoutProgressGauge(progress: .Sample.readingMid)
        LookoutProgressGauge(progress: .Sample.pausedLowPower)
        LookoutProgressGauge(progress: .Sample.upToDate())
        LookoutProgressGauge(progress: .Sample.failed)
        LookoutProgressGauge(progress: .Sample.counting, reduceMotion: true)
    }
    .padding(24)
}
#endif
