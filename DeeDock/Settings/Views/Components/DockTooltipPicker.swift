import SwiftUI

/// A gallery of complete presets. Thumbnails use the production label renderer without timers.
struct DockTooltipPicker: View {
    @Binding var selection: DockTooltipPreset
    let edge: DockEdge
    let reduceTransparency: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
            ForEach(DockTooltipPreset.allCases) { preset in
                Button { selection = preset } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            if preset == .off { Image(systemName: "text.bubble.slash").font(.title2).foregroundStyle(.secondary) }
                            else {
                                DockTooltipArtwork(name: String(localized: .tooltipSampleApp),
                                    icon: NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil),
                                    preset: preset, edge: edge, maximumWidth: 140, reduceTransparency: reduceTransparency)
                            }
                        }.frame(height: 58)
                        Text(preset.title).font(.callout.weight(.medium))
                        Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 136, alignment: .top)
                    .padding(10)
                    .background(selection == preset ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if selection == preset { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).padding(6) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(preset.title))
                .accessibilityHint(Text(preset.subtitle))
                .accessibilityAddTraits(selection == preset ? [.isSelected] : [])
            }
        }.padding(14)
    }
}

#if DEBUG
#Preview("App-name presets") {
    @Previewable @State var preset: DockTooltipPreset = .classic
    ScrollView { DockTooltipPicker(selection: $preset, edge: .bottom, reduceTransparency: false) }.frame(width: 620, height: 700)
}
#Preview("App-name presets, dark and opaque") {
    @Previewable @State var preset: DockTooltipPreset = .spectrum
    ScrollView { DockTooltipPicker(selection: $preset, edge: .right, reduceTransparency: true) }
        .preferredColorScheme(.dark).frame(width: 620, height: 700)
}
#endif
