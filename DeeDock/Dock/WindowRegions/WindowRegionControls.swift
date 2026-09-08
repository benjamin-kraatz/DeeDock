import SwiftUI

/// The four regions worth one click. Anything else is drawn on the preview or tuned with sliders.
///
/// Presets name what they select, so the common cases never require a drag: a window's whole
/// surface, one of its halves, or the middle where progress and status usually live.
struct WindowRegionPresetPicker: View {
    @Binding var region: NormalizedWindowRegion
    let tint: Color

    private static let presets: [(LocalizedStringResource, NormalizedWindowRegion)] = [
        (.regionWholeWindow, NormalizedWindowRegion()),
        (.regionPresetTop, NormalizedWindowRegion(x: 0, y: 0, width: 1, height: 0.5)),
        (.regionPresetBottom, NormalizedWindowRegion(x: 0, y: 0.5, width: 1, height: 0.5)),
        (.regionPresetCenter, NormalizedWindowRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                button(preset.0, region: preset.1)
            }
        }
    }

    private func button(_ label: LocalizedStringResource, region preset: NormalizedWindowRegion) -> some View {
        let selected = region.clamped == preset.clamped
        return Button {
            region = preset
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
        .background(selected ? tint.opacity(0.16) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(selected ? 0.5 : 0), lineWidth: 1) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The same selection as four numbers, for precision and for keyboard-only operation.
///
/// Collapsed by default: dragging on the preview is the primary way to choose a region, and the
/// percentages exist for the cases a drag cannot hit exactly.
struct WindowRegionFineTuning: View {
    @Binding var region: NormalizedWindowRegion
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Grid(alignment: .leading) {
                control(.regionX, keyPath: \.x, range: 0...0.95)
                control(.regionY, keyPath: \.y, range: 0...0.95)
                control(.regionWidth, keyPath: \.width, range: 0.05...1)
                control(.regionHeight, keyPath: \.height, range: 0.05...1)
            }
            .padding(.top, 6)
        } label: {
            Text(.regionFineTune).font(.callout)
        }
    }

    private func control(_ label: LocalizedStringResource,
                         keyPath: WritableKeyPath<NormalizedWindowRegion, Double>,
                         range: ClosedRange<Double>) -> some View {
        let value = Binding<Double> {
            region.clamped[keyPath: keyPath]
        } set: { updated in
            var next = region.clamped
            next[keyPath: keyPath] = updated
            region = next.clamped
        }
        return GridRow {
            Text(label).font(.callout)
            Slider(value: value, in: range, step: 0.01).accessibilityLabel(Text(label))
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .font(.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

#if DEBUG
private struct WindowRegionControlsHarness: View {
    @State private var region = NormalizedWindowRegion(x: 0.1, y: 0.2, width: 0.5, height: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowRegionPresetPicker(region: $region, tint: .accentColor)
            WindowRegionFineTuning(region: $region)
        }
        .padding()
        .frame(width: 380)
    }
}

#Preview("Region controls") { WindowRegionControlsHarness() }
#endif
