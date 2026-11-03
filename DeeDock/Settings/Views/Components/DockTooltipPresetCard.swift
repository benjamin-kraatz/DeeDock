import SwiftUI

/// One selectable app-name preset in the gallery.
///
/// The card reports when the pointer or keyboard focus arrives and when both have left; the
/// gallery decides which single card replays. VoiceOver reads the preset's title and description,
/// never the sample artwork.
struct DockTooltipPresetCard: View {
    let preset: DockTooltipPreset
    let isSelected: Bool
    let phase: DockTooltipPresetPlayback.Phase
    let edge: DockEdge
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let select: () -> Void
    /// Called with true when hover or keyboard focus begins, and false once neither remains.
    let activeChanged: (Bool) -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                Group {
                    if preset == .off {
                        Image(systemName: "text.bubble.slash").font(.title2).foregroundStyle(.secondary)
                    } else {
                        DockTooltipPresetThumbnail(preset: preset, phase: phase, edge: edge,
                                                   reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                    }
                }
                .frame(height: 86)
                Text(preset.title).font(.callout.weight(.medium))
                Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .top)
            .padding(10)
            .settingsSelectionCard(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovering = $0 }
        .onChange(of: hovering || focused) { _, active in activeChanged(active) }
        .accessibilityLabel(Text(preset.title))
        .accessibilityHint(Text(preset.subtitle))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
