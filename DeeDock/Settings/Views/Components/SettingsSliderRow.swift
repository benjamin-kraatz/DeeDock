import SwiftUI

/// A continuous setting: a labeled slider with a precise, editable value pill.
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

    private var snapped: Binding<Double> {
        Binding(get: { value },
                set: { proposed in
                    let stepped = (proposed / step).rounded() * step
                    value = min(max(stepped, range.lowerBound), range.upperBound)
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                SettingsValueField(title: title, unit: unit, value: $value, range: range, step: step)
            }
            HStack(spacing: 9) {
                endcap(minimumSymbol)
                Slider(value: snapped, in: range) { Text(title) }
                    .labelsHidden()
                endcap(maximumSymbol)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
