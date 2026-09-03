import SwiftUI

/// Sparkles that pop in and out around the icon's border.
///
/// Each of the slots below runs its own birth-to-death cycle: a sparkle fades up from
/// nothing, peaks, and shrinks away again, and the next one appears somewhere else. Position,
/// size and colour are redrawn per generation from the variant's seed, so an application
/// keeps its own repertoire of sparkle sites without ever showing a fixed constellation.
/// They sit on a ring rather than over the middle, which keeps the artwork readable.
struct DockStardust: View {
    let size: CGFloat
    let variant: DockIndicatorVariant
    let animated: Bool

    private static let slots = 4
    /// Matches `DockIconAura.period`: elapsed time is wrapped, and every rate below is a
    /// whole number of cycles within it, so the wrap is seamless.
    private static let period: Double = 60
    private static let palette: [Color] = [.yellow, .pink, .cyan, .mint, .orange, .white]

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                field(turn: context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period) / Self.period)
            }
        } else {
            field(turn: 0)
        }
    }

    private func field(turn: Double) -> some View {
        ZStack {
            ForEach(0..<Self.slots, id: \.self) { slot in
                sparkle(slot, turn: turn)
            }
        }
        .frame(width: size, height: size)
    }

    private func sparkle(_ slot: Int, turn: Double) -> some View {
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
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, y: 1)
            .opacity(envelope)
            .rotationEffect(.degrees(life * 90 + variant.draw(salt + 6) * 360))
            .position(x: size * (0.5 + cos(angle) * radius), y: size * (0.5 + sin(angle) * radius))
    }
}

#if DEBUG
#Preview("Six repertoires, sparkling") {
    HStack(spacing: 12) {
        ForEach(["finder", "mail", "safari", "terminal", "music", "photos"], id: \.self) { identity in
            RoundedRectangle(cornerRadius: 12).fill(.indigo.gradient)
                .padding(6)
                .frame(width: 72, height: 72)
                .modifier(DockIconIndicator(style: .stardust, running: true, size: 72,
                                            variant: DockIndicatorVariant(identity: identity), animated: true))
        }
    }
    .padding(24).background(.black)
}
#endif
