import SwiftUI

/// Sparkles that pop in and out around the icon's border.
///
/// Each of the slots below runs its own birth-to-death cycle: a sparkle fades up from
/// nothing, peaks, and shrinks away again, and the next one appears somewhere else. Position,
/// size and colour are redrawn per generation from the variant's seed, so an application
/// keeps its own repertoire of sparkle sites without ever showing a fixed constellation.
/// They sit on a ring rather than over the middle, which keeps the artwork readable.
///
/// An app running in background shows the same constellation in ``DockIndicatorMutedInk`` gray,
/// standing still. The coloured and gray fields share one clock and crossfade under the caller's
/// animation, so no sparkle moves while the colour drains out or comes back.
struct DockStardust: View {
    let size: CGFloat
    let variant: DockIndicatorVariant
    /// Whether the sparkles twinkle while the app runs. Static sparkles show a fixed constellation.
    let animated: Bool
    /// `.running` shows the coloured field, `.background` the gray one.
    var state: DockRunningState = .running
    @State private var clock = StardustClock()

    private static let slots = 4
    /// Elapsed time is wrapped to this period, and every rate below is a whole number of
    /// cycles within it, so the wrap is seamless.
    fileprivate static let period: Double = 60
    private static let palette: [Color] = [.yellow, .pink, .cyan, .mint, .orange, .white]

    private var twinkling: Bool { animated && state == .running }

    var body: some View {
        if animated {
            // Pausing holds the clock instead of resetting it: the sparkles stay where they were
            // while the gray field fades in, and carry on from there when the app runs again.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !twinkling)) { context in
                fields(turn: clock.turn(at: context.date, paused: !twinkling))
            }
        } else {
            fields(turn: 0)
        }
    }

    private func fields(turn: Double) -> some View {
        ZStack {
            field(turn: turn, muted: false).opacity(state == .running ? 1 : 0)
            field(turn: turn, muted: true).opacity(state == .background ? 1 : 0)
        }
        .frame(width: size, height: size)
    }

    private func field(turn: Double, muted: Bool) -> some View {
        ZStack {
            ForEach(0..<Self.slots, id: \.self) { slot in
                sparkle(slot, turn: turn, muted: muted)
            }
        }
    }

    private func sparkle(_ slot: Int, turn: Double, muted: Bool) -> some View {
        // Whole numbers of lives per cycle, so the wrap lands exactly on a generation edge.
        let lives = 8 + (variant.draw(slot * 16) * 9).rounded(.down)
        let offset = variant.draw(slot * 16 + 1)
        let clock = turn * lives + offset
        // Generations repeat within one cycle, which is what keeps the wrap invisible.
        let generation = Int(clock.rounded(.down).truncatingRemainder(dividingBy: lives))
        let life = clock - clock.rounded(.down)
        let salt = slot * 16 + generation * 211

        // Smooth birth and death: zero at both ends, with a brief hold near the peak.
        let envelope = pow(sin(life * .pi), 0.65)
        // Evenly spaced sectors keep two live sparkles from landing on top of each other.
        let sector = (Double(slot) + variant.draw(salt + 2)) / Double(Self.slots)
        let angle = sector * 2 * .pi
        let radius = 0.30 + variant.draw(salt + 3) * 0.15
        let scale = 0.13 + variant.draw(salt + 4) * 0.14
        let color = Self.palette[Int(variant.draw(salt + 5) * Double(Self.palette.count)) % Self.palette.count]
        // A sparkle grows slightly as it dies, which reads as a flash rather than a fade.
        let spread = 0.55 + 0.75 * life
        return Image(systemName: "sparkle")
            .font(.system(size: size * scale * spread * (0.4 + 0.6 * envelope), weight: .bold))
            .foregroundStyle(muted ? DockIndicatorMutedInk.fill : color)
            // The hard drop shadow is what keeps a sparkle visible on a light icon; muted, it softens.
            .shadow(color: muted ? DockIndicatorMutedInk.outline : .black, radius: 0, y: 1)
            .opacity(envelope)
            .rotationEffect(.degrees(life * 90 + variant.draw(salt + 6) * 360))
            .position(x: size * (0.5 + cos(angle) * radius), y: size * (0.5 + sin(angle) * radius))
    }
}

/// Elapsed sparkle time that survives pauses.
///
/// A reference type so the timeline's content can settle it while rendering, without a state
/// write that would invalidate the view mid-update. Settling is idempotent: a paused clock keeps
/// returning the date it paused at, however often the content is re-evaluated, and resuming
/// folds the paused interval into `offset` exactly once.
private final class StardustClock {
    private var offset: TimeInterval = 0
    private var pausedAt: Date?

    /// The field's position in its cycle at `date`, or where it stood when it paused.
    func turn(at date: Date, paused: Bool) -> Double {
        let now: Date
        if paused {
            let held = pausedAt ?? date
            pausedAt = held
            now = held
        } else {
            if let pausedAt {
                offset += date.timeIntervalSince(pausedAt)
                self.pausedAt = nil
            }
            now = date
        }
        let elapsed = now.timeIntervalSinceReferenceDate - offset
        return elapsed.truncatingRemainder(dividingBy: DockStardust.period) / DockStardust.period
    }
}

#if DEBUG
#Preview("Six repertoires, sparkling") {
    HStack(spacing: 12) {
        ForEach(["finder", "mail", "safari", "terminal", "music", "photos"], id: \.self) { identity in
            RoundedRectangle(cornerRadius: 12).fill(.indigo.gradient)
                .padding(6)
                .frame(width: 72, height: 72)
                .modifier(DockIconIndicator(style: .stardust, state: .running, size: 72,
                                            variant: DockIndicatorVariant(identity: identity), animated: true))
        }
    }
    .padding(24).background(.black)
}

/// Flip the toggle while the sparkles move: they hold still and go gray, then resume in place.
#Preview("Running in background, held in place") {
    @Previewable @State var background = false
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ForEach(["finder", "mail", "safari"], id: \.self) { identity in
                RoundedRectangle(cornerRadius: 12).fill(.indigo.gradient)
                    .padding(6)
                    .frame(width: 72, height: 72)
                    .modifier(DockIconIndicator(style: .stardust, state: background ? .background : .running, size: 72,
                                                variant: DockIndicatorVariant(identity: identity), animated: true))
            }
        }
        Toggle(isOn: $background) { Text(.appStatusRunningInBackground) }
    }
    .padding(24).background(.regularMaterial)
}
#endif
