import SwiftUI

/// Side-by-side steady states and a cancellable timing sample. Never touches live dock state.
struct DockFadingPreview: View {
    let settings: DockSettings
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    @State private var playbackID: UUID?
    @State private var fraction: Double = 0
    @State private var playing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                sample(title: .appearanceNormal, idleFraction: 0)
                sample(title: .appearanceIdle, idleFraction: 1)
            }
            if playing {
                sample(title: .appearancePlayback, idleFraction: fraction)
            }
            Button(.behaviorPlayPreview, systemImage: "play.fill") { playbackID = UUID() }
                .disabled(!settings.fadeWhenIdle || reduceTransparency)
        }
        .padding(14)
        .task(id: playbackID) {
            guard playbackID != nil else { return }
            playing = true
            withAnimation(nil) { fraction = 0 }
            do {
                try await Task.sleep(for: .seconds(settings.idleDelay))
                try Task.checkCancellation()
                let fade = reduceMotion ? min(0.1, settings.fadeOutDuration) : settings.fadeOutDuration
                withAnimation(fade == 0 ? nil : .easeInOut(duration: fade)) { fraction = 1 }
                try await Task.sleep(for: .seconds(fade + 1))
                try Task.checkCancellation()
                let restore = reduceMotion ? 0 : settings.restoreDuration
                withAnimation(restore == 0 ? nil : .easeInOut(duration: restore)) { fraction = 0 }
                try await Task.sleep(for: .seconds(restore))
                try Task.checkCancellation()
                playing = false
            } catch { /* The view or its configuration owns cancellation. */ }
        }
        .onChange(of: settings) { cancelPlayback() }
        .onChange(of: reduceMotion) { cancelPlayback() }
        .onChange(of: reduceTransparency) { cancelPlayback() }
    }

    private func cancelPlayback() {
        playbackID = nil
        playing = false
        withAnimation(nil) { fraction = 0 }
    }

    private func sample(title: LocalizedStringResource, idleFraction: Double) -> some View {
        let layout = DockGeometry.layout(count: 4, favoriteCount: 4,
            availableLength: 1000, settings: settings)
        let scale = min(0.5, 220 / max(layout.viewportSize.width, layout.viewportSize.height))
        return VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DockSampleView(layout: layout, runningIndicatorStyle: settings.runningIndicatorStyle,
                           appearanceSettings: settings, idleFraction: idleFraction,
                           reduceMotionOverride: reduceMotion, reduceTransparencyOverride: reduceTransparency)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: layout.viewportSize.width * scale,
                       height: layout.viewportSize.height * scale, alignment: .topLeading)
        }.frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Floating icons, idle at zero") {
    DockFadingPreview(settings: DockSettings(showBackground: false, fadeWhenIdle: true, idleOpacity: 0))
        .frame(width: 550).padding()
}
#Preview("Side dock, background-only fading") {
    DockFadingPreview(settings: DockSettings(edge: .left,
        fadeWhenIdle: true, fadeTarget: .backgroundOnly)).frame(width: 550).padding()
}
#Preview("Reduced transparency, dark") {
    DockFadingPreview(settings: DockSettings(fadeWhenIdle: true),
                      reduceMotionOverride: true, reduceTransparencyOverride: true)
        .preferredColorScheme(.dark).frame(width: 550).padding()
}
#endif
