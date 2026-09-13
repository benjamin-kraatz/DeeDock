import SwiftUI

/// Opens the Atmosphere pane: the section's icon, what the feature does, and its master switch.
struct AtmosphereHeaderCard: View {
    @Binding var isOn: Bool

    var body: some View {
        SettingsCard {
            HStack(spacing: 14) {
                SettingsIconTile(glyph: SettingsSection.atmosphere.glyph,
                                 colors: SettingsSection.atmosphere.tileColors, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(.atmosphereTitle)
                        .font(.headline)
                    Text(.atmosphereSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: SettingsMetrics.controlSpacing)
                Toggle(isOn: $isOn) { Text(.atmosphereEnabled) }
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 12)
        }
    }
}

#if DEBUG
#Preview("Header") {
    @Previewable @State var isOn = true
    AtmosphereHeaderCard(isOn: $isOn).padding(24).frame(width: 620)
}
#endif
