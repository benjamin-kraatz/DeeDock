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
        // The timeline shares the dock's viewport, and the presentation transform below moves
        // both together, which keeps the track over the glass it measures.
        let timeline = interaction.timeline
        ZStack(alignment: .topLeading) {
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
                drawsBackground: true,
                ambientAnimated: visibility.exposesContent && visibility.progress == 0,
                primaryAppAction: store.performPrimaryAction,
                openApp: store.open,
                togglePin: store.toggleFavorite,
                dismissError: { store.errorMessage = nil }
            )
            DockRumoursOverlay(store: store, interaction: interaction,
                enabled: visibility.progress == 0 && !reduceMotion,
                reduceTransparency: reduceTransparency)
            if let timeline, timeline.isActive(on: store.displayID) {
                DockTimelineOverlay(
                    presentation: timeline.presentation,
                    layout: interaction.layout,
                    scrollOffset: interaction.scrollOffset,
                    end: { timeline.end() },
                    // The panel accepts mouse events only over reported regions. The glance card
                    // borrows the callout region so Done stays clickable; an error banner owns the
                    // same region, and it wins because a failure must remain dismissable.
                    calloutRectChanged: { rect in
                        guard store.errorMessage == nil else { return }
                        interaction.errorRect = rect
                    }
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
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
