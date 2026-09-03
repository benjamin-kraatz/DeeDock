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
        let size = CGSize(width: interaction.layout.viewportWidth, height: interaction.layout.panelHeight)
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: size, reduceMotion: reduceMotion)
        DockContentView(
            items: store.items,
            launchingIDs: store.launching,
            selectedID: store.selectedID,
            keyboardFocus: store.keyboardFocus,
            errorMessage: store.errorMessage,
            interaction: interaction,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            openApp: store.open,
            togglePin: store.toggleFavorite,
            dismissError: { store.errorMessage = nil }
        )
        .modifier(DockPresentationModifier(sample: sample, size: size))
        .accessibilityHidden(!visibility.exposesContent)
        .allowsHitTesting(visibility.exposesContent)
        .offset(x: interaction.contentOrigin.x, y: interaction.contentOrigin.y)
        .frame(width: interaction.windowSize.width, height: interaction.windowSize.height, alignment: .topLeading)
        .clipped()
    }
}
