import SwiftUI

/// Connects the live dock store to presentation without starting services from a view.
///
/// Preview `DockContentView` with sample values instead of constructing a live workspace store.
struct DockView: View {
    let store: DockStore
    let interaction: DockInteraction
    let visibility: DockVisibilityController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let size = interaction.layout.viewportSize
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: size, reduceMotion: reduceMotion, edge: interaction.layout.edge)
        DockContentView(
            items: store.items,
            entries: store.entries,
            launchingIDs: store.launching,
            selectedTarget: store.selectedTarget,
            keyboardFocus: store.keyboardFocus,
            errorMessage: store.errorMessage,
            interaction: interaction,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            openApp: store.open,
            togglePin: store.toggleFavorite,
            dismissError: { store.errorMessage = nil }
        )
        .id(interaction.layout.edge.isVertical)
        .modifier(DockPresentationModifier(sample: sample, size: size))
        .accessibilityHidden(!visibility.exposesContent)
        .allowsHitTesting(visibility.exposesContent)
        // The native panel animates its screen frame. Keep this coordinate conversion immediate
        // so reported button rectangles and inverse pointer mapping use the same local origin.
        .animation(nil) { content in
            content.offset(x: interaction.contentOrigin.x, y: interaction.contentOrigin.y)
                .frame(width: interaction.windowSize.width, height: interaction.windowSize.height, alignment: .topLeading)
                .clipped()
        }
    }
}
