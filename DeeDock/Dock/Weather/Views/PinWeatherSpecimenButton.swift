import SwiftUI

/// A clickable sample pin: rusted through ``PinWeatherLook``, polished clean when used.
///
/// Hover lifts the icon the way the dock does, and a use plays a light sweep across the artwork
/// so the reset reads as polish rather than a cut. Reduce Motion drops the lift and the sweep.
struct PinWeatherSpecimenButton: View {
    let specimen: PinWeatherSpecimen
    let intensity: Double
    let unusedDays: Int
    let use: () -> Void

    private let size: CGFloat = 54
    @State private var hovering = false
    @State private var sweep: CGFloat = -1.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var squircle: RoundedRectangle {
        // Matches the squircle proportion of macOS artwork so the rust lands where it would on a real pin.
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
    }

    var body: some View {
        Button(action: use) {
            artwork
                .overlay { shine }
                .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
                .scaleEffect(hovering && !reduceMotion ? 1.12 : 1, anchor: .bottom)
                .animation(.spring(duration: 0.3, bounce: 0.35), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onChange(of: specimen.restores) {
            guard !reduceMotion else { return }
            sweep = -1.4
            withAnimation(.easeOut(duration: 0.75)) { sweep = 1.4 }
        }
        .accessibilityLabel(Text(.pinWeatherSampleIcon(Int((specimen.age * Double(unusedDays)).rounded()))))
        .accessibilityAction(named: Text(.pinWeatherHeroUse), use)
    }

    private var artwork: some View {
        squircle
            .fill(LinearGradient(colors: specimen.colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: specimen.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            }
            .overlay {
                // Top gloss, so the clean state looks freshly polished next to the rusted ones.
                squircle.fill(LinearGradient(colors: [.white.opacity(0.28), .clear],
                                             startPoint: .top, endPoint: .center))
            }
            .frame(width: size, height: size)
            .clipShape(squircle)
            .modifier(PinWeatherLook(intensity: intensity))
    }

    private var shine: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: size * 0.45, height: size * 1.6)
            .rotationEffect(.degrees(22))
            .offset(x: sweep * size)
            .frame(width: size, height: size)
            .clipShape(squircle)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
