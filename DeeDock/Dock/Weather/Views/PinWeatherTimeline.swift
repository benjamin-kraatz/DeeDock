import SwiftUI

/// The showcase's age rail: clean at the left, rust from the threshold, full rust at twice it.
///
/// One dot per sample pin slides along the rail as it ages and springs back when it is used.
/// Stage labels carry the real day numbers, so moving the threshold slider relabels them.
struct PinWeatherTimeline: View {
    let unusedDays: Int
    let specimens: [PinWeatherSpecimen]

    private let railHeight: CGFloat = 5
    private let dotSize: CGFloat = 11
    private let labelWidth: CGFloat = 130

    /// Where a threshold-unit age sits along the rail, `0...1`.
    private func fraction(_ age: Double) -> Double {
        min(1, max(0, age / PinWeatherSpecimen.maximumAge))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                rail
                    .frame(width: width, height: railHeight)
                    .offset(y: (dotSize - railHeight) / 2)
                ForEach(stages, id: \.age) { stage in
                    Capsule()
                        .fill(.white.opacity(0.55))
                        .frame(width: 1.5, height: dotSize + 4)
                        .offset(x: fraction(stage.age) * width - 0.75, y: -2)
                }
                ForEach(specimens) { specimen in
                    Circle()
                        .fill(LinearGradient(colors: specimen.colors, startPoint: .top, endPoint: .bottom))
                        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: fraction(specimen.age) * width - dotSize / 2)
                }
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    stageLabel(stage)
                        .frame(width: labelWidth, alignment: index == 0 ? .leading : .center)
                        .offset(x: index == 0 ? 0 : fraction(stage.age) * width - labelWidth / 2,
                                y: dotSize + 8)
                }
            }
        }
        .frame(height: dotSize + 8 + 30)
        .accessibilityHidden(true)
    }

    private var stages: [(age: Double, title: LocalizedStringResource, day: LocalizedStringResource)] {
        [(0, .pinWeatherPreviewClean, .pinWeatherHeroToday),
         (1, .pinWeatherPreviewStarts, .pinWeatherHeroDay(unusedDays)),
         (2, .pinWeatherPreviewHeavy, .pinWeatherHeroDay(unusedDays * 2))]
    }

    private var rail: some View {
        let start = fraction(1)
        let full = fraction(2)
        return Capsule()
            .fill(LinearGradient(stops: [
                .init(color: Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.85), location: 0),
                .init(color: Color(red: 0.70, green: 0.70, blue: 0.70).opacity(0.7), location: start * 0.8),
                .init(color: Color(red: 0.88, green: 0.52, blue: 0.24), location: start),
                .init(color: Color(red: 0.70, green: 0.28, blue: 0.10), location: full),
                .init(color: Color(red: 0.40, green: 0.15, blue: 0.07), location: 1)
            ], startPoint: .leading, endPoint: .trailing))
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
    }

    private func stageLabel(_ stage: (age: Double, title: LocalizedStringResource, day: LocalizedStringResource)) -> some View {
        VStack(spacing: 1) {
            Text(stage.title)
                .font(.caption.weight(.semibold))
            Text(stage.day)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
