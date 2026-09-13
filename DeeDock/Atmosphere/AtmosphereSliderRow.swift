import SwiftUI

/// A unitless 0…1 amount: label on the leading edge, a fixed-width slider between two glyphs.
///
/// Atmosphere amounts are feel rather than measurements, so unlike `SettingsSliderRow` this row
/// carries no numeric field and keeps the height of an ordinary row.
struct AtmosphereSliderRow: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let minimumSymbol: String
    let maximumSymbol: String

    var body: some View {
        SettingsRow(title: title) {
            HStack(spacing: 8) {
                endcap(minimumSymbol)
                Slider(value: $value, in: range) { Text(title) }
                    .labelsHidden()
                    .controlSize(.small)
                endcap(maximumSymbol)
            }
            .frame(width: 260)
        }
    }

    private func endcap(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}
