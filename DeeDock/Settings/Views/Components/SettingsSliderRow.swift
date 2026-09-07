import SwiftUI

/// A continuous setting: a labeled slider with an adjacent standard numeric field.
///
/// The slider is unstepped so macOS does not draw a tick rail across wide ranges; values are
/// snapped to `step` in the binding instead, matching the precision that gets persisted.
struct SettingsSliderRow: View {
    let title: LocalizedStringResource
    let unit: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// Optional glyphs marking the low and high ends of the range.
    var minimumSymbol: String?
    var maximumSymbol: String?
    /// When supplied, offers a reset after the value differs from this factory default.
    var defaultValue: Double? = nil

    private var snapped: Binding<Double> {
        Binding(get: { value },
                set: { proposed in
                    let stepped = (proposed / step).rounded() * step
                    value = min(max(stepped, range.lowerBound), range.upperBound)
                })
    }

    var body: some View {
        SettingsStackedRow(title: title) {
            HStack(spacing: 12) {
                endcap(minimumSymbol)
                Slider(value: snapped, in: range) { Text(title) }
                    .labelsHidden()
                endcap(maximumSymbol)
                SettingsValueField(title: title, unit: unit, value: $value, range: range, step: step)
                if let defaultValue {
                    SettingsResetButton(title: title) { value = defaultValue }
                        .disabled(value == defaultValue)
                }
            }
        }
    }

    @ViewBuilder private func endcap(_ symbol: String?) -> some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
