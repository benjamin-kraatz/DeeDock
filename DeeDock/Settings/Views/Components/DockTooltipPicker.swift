import SwiftUI

/// A gallery of complete presets. Thumbnails use the production label renderer and rest as static
/// samples; hovering or focusing one replays its hover delay and entrance.
///
/// The gallery owns one `DockTooltipPresetPlayback`, so only one card animates at a time. Selection,
/// edge, and Reduce Motion changes, closing or deactivating the Settings window, and disappearing
/// all cancel the pending reveal.
struct DockTooltipPicker: View {
    @Binding var selection: DockTooltipPreset
    let edge: DockEdge
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var playback = DockTooltipPresetPlayback()

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
            ForEach(DockTooltipPreset.allCases) { preset in
                DockTooltipPresetCard(preset: preset, isSelected: selection == preset,
                                      phase: playback.phase(for: preset), edge: edge,
                                      reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                      select: { selection = preset },
                                      activeChanged: { active in
                                          if active { playback.play(preset, reduceMotion: reduceMotion) }
                                          else { playback.stop(preset) }
                                      })
            }
        }
        .padding(SettingsMetrics.rowInset)
        .background {
            SettingsWindowLifecycle(closed: { playback.stop() },
                                    activityChanged: { active in if !active { playback.stop() } })
        }
        .onChange(of: selection) { _, _ in playback.stop() }
        .onChange(of: edge) { _, _ in playback.stop() }
        .onChange(of: reduceMotion) { _, _ in playback.stop() }
        .onDisappear { playback.stop() }
    }
}

#if DEBUG
#Preview("App-name presets") {
    @Previewable @State var preset: DockTooltipPreset = .classic
    ScrollView {
        DockTooltipPicker(selection: $preset, edge: .bottom, reduceMotion: false, reduceTransparency: false)
    }
    .frame(width: 620, height: 700)
}
#Preview("App-name presets, dark and opaque") {
    @Previewable @State var preset: DockTooltipPreset = .spectrum
    ScrollView {
        DockTooltipPicker(selection: $preset, edge: .right, reduceMotion: false, reduceTransparency: true)
    }
    .preferredColorScheme(.dark).frame(width: 620, height: 700)
}

/// Plays one card as soon as it appears, the way hovering does, so the canvas shows the delay and
/// entrance without a pointer. Click a card to replay it. `reduceMotion` is a local flag, not an
/// environment override.
private struct DockTooltipPlaybackSample: View {
    let preset: DockTooltipPreset
    var reduceMotion = false
    @State private var playback = DockTooltipPresetPlayback()

    var body: some View {
        DockTooltipPresetCard(preset: preset, isSelected: false, phase: playback.phase(for: preset),
                              edge: .bottom, reduceMotion: reduceMotion, reduceTransparency: false,
                              select: { playback.play(preset, reduceMotion: reduceMotion) },
                              activeChanged: { _ in })
            .frame(width: 180)
            .onAppear { playback.play(preset, reduceMotion: reduceMotion) }
            .onDisappear { playback.stop() }
    }
}

#Preview("Hover playback") {
    HStack(alignment: .top, spacing: 8) {
        DockTooltipPlaybackSample(preset: .nameCard)
        DockTooltipPlaybackSample(preset: .speechBubble)
        DockTooltipPlaybackSample(preset: .leadingTag)
        DockTooltipPlaybackSample(preset: .dockCaption)
        DockTooltipPlaybackSample(preset: .pop, reduceMotion: true)
    }
    .padding(16)
}
#endif
