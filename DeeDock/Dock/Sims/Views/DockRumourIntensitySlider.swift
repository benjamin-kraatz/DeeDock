import SwiftUI

/// Three discrete gossip styles, available in both Debug and Release settings.
struct DockRumourIntensitySlider: View {
    let value: DockRumourIntensity
    let setValue: (DockRumourIntensity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(.simsGossipIntensity)
                Spacer()
                Text(value.title).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value.rawValue) }, set: {
                if let style = DockRumourIntensity(rawValue: Int($0.rounded())) { setValue(style) }
            }), in: 0...2, step: 1)
                .accessibilityLabel(Text(.simsGossipIntensity))
                .accessibilityValue(Text(value.title))
            Text(value.help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Gossip styles") {
    VStack(spacing: 24) {
        ForEach(DockRumourIntensity.allCases, id: \.rawValue) { style in
            DockRumourIntensitySlider(value: style, setValue: { _ in })
        }
    }
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
}
#endif
