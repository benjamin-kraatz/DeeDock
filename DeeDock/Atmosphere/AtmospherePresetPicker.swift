import SwiftUI

/// The four presets as one row of tiles, sharing the settings gallery selection finish.
struct AtmospherePresetPicker: View {
    @Binding var selection: AtmospherePreset

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: AtmospherePreset.allCases.count),
                  spacing: 8) {
            ForEach(AtmospherePreset.allCases, id: \.self) { preset in
                Button { selection = preset } label: {
                    VStack(spacing: 7) {
                        Image(systemName: preset.symbol)
                            .font(.title2)
                            .foregroundStyle(selection == preset ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(height: 26)
                        Text(preset.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .settingsSelectionCard(isSelected: selection == preset)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(preset.title))
                .accessibilityAddTraits(selection == preset ? [.isSelected] : [])
            }
        }
        .padding(SettingsMetrics.rowInset)
    }
}

private extension AtmospherePreset {
    var symbol: String {
        switch self {
        case .sixtyNine: "flame"
        case .minimal: "circle.dashed"
        case .focus: "scope"
        case .party: "party.popper"
        }
    }
}

#if DEBUG
#Preview("Presets") {
    @Previewable @State var preset = AtmospherePreset.party
    AtmospherePresetPicker(selection: $preset).frame(width: 620)
}
#endif
