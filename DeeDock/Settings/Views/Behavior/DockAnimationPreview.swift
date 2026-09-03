import SwiftUI

/// Explicit playback uses the production effects and scheduler with inert symbol tiles, never live apps.
struct DockAnimationPreview: View {
    let style: DockAnimationStyle
    let duration: Double
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var controller = DockVisibilityController()
    @State private var playback: Task<Void, Never>?
    private let size = CGSize(width: 300, height: 128)

    var body: some View {
        VStack(spacing: 6) {
            DockAppearancePreview(iconSize: 48, magnification: 1)
                .frame(width: size.width, height: size.height)
                .modifier(DockPresentationModifier(sample: DockAnimationGeometry.sample(style: style, progress: controller.progress,
                                                                                       size: size, reduceMotion: reduceMotion), size: size))
                .frame(width: 380, height: 208).clipped().accessibilityHidden(true)
            Button(.behaviorPlayPreview, systemImage: "play.fill", action: play)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 14)
        .background { SettingsWindowLifecycle { reset() } }
        .onChange(of: style) { _, _ in reset() }
        .onChange(of: duration) { _, _ in reset() }
        .onChange(of: reduceMotion) { _, _ in reset() }
        .onDisappear { reset() }
    }
    private func reset() {
        playback?.cancel(); playback = nil; controller.stop(); controller = DockVisibilityController()
    }
    private func play() {
        reset()
        var settings = DockBehaviorSettings()
        settings.autoHide = true; settings.hideDelay = 0; settings.revealDelay = 0
        settings.animationStyle = style; settings.animationDuration = duration
        controller.configure(settings, reduceMotion: reduceMotion)
        controller.update(activation: false, retained: false, held: false)
        let current = controller
        let wait = (reduceMotion ? min(0.1, duration) : duration) + 0.25
        playback = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            guard !Task.isCancelled else { return }
            current.update(activation: false, retained: false, held: true)
        }
    }
}
