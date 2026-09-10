import SwiftUI

/// How long a pin may sit unused before rust begins: a large readout, a slider, and presets.
struct PinWeatherThresholdCard: View {
    let unusedDays: Int
    let setUnusedDays: (Int) -> Void

    private static let presets: [(days: Int, title: LocalizedStringResource)] = [
        (7, .pinWeatherPresetWeek), (14, .pinWeatherPresetTwoWeeks),
        (PinWeatherLimits.defaultUnusedDays, .pinWeatherPresetMonth), (90, .pinWeatherPresetQuarter)
    ]

    private var range: ClosedRange<Double> {
        Double(PinWeatherLimits.unusedDays.lowerBound)...Double(PinWeatherLimits.unusedDays.upperBound)
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(.pinWeatherUnusedDays)
                        .foregroundStyle(.secondary)
                    Text(.pinWeatherDaysCount(unusedDays))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(unusedDays)))
                        .animation(.snappy, value: unusedDays)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                // Snapped in the binding rather than stepped, so macOS draws no tick rail across 90 days.
                Slider(value: Binding(get: { Double(unusedDays) },
                                      set: { setUnusedDays(Int($0.rounded())) }),
                       in: range) {
                    Text(.pinWeatherUnusedDays)
                }
                .labelsHidden()
                .accessibilityValue(Text(.pinWeatherDaysCount(unusedDays)))
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.days) { preset in
                        Button { setUnusedDays(preset.days) } label: { Text(preset.title) }
                            .buttonStyle(PinWeatherPresetStyle(selected: preset.days == unusedDays))
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowInset + 2)
            .padding(.vertical, 14)
        }
    }
}

/// A capsule chip that fills with the accent color when it matches the current value.
private struct PinWeatherPresetStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
            .animation(.snappy(duration: 0.2), value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Threshold") {
    @Previewable @State var days = 30
    PinWeatherThresholdCard(unusedDays: days, setUnusedDays: { days = $0 })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
