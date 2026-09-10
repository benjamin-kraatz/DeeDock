import SwiftUI

/// Connects the live dock store to presentation without starting services from a view.
///
/// Preview `DockContentView` with sample values instead of constructing a live workspace store.
struct DockView: View {
    let launcher: LauncherState
    let store: DockStore
    let interaction: DockInteraction
    let visibility: DockVisibilityController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if launcher.isPresented {
            ZStack(alignment: .topLeading) {
                LauncherView(state: launcher, dockCornerRadius: interaction.idleFade.settings.cornerRadius)
                // The dock's own contents keep their screen position inside the launcher's larger
                // window while they fade, so the two sides of the morph cross over in place. They
                // sit above the launcher's material: drawn underneath it they would be seen
                // through the glass, which frosts them into a glow instead of a fade.
                dock(drawsBackground: false)
                    .offset(x: launcher.dockContentOffset.width, y: launcher.dockContentOffset.height)
                    .modifier(DockMorphFade(phase: launcher.morph))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            dock()
        }
    }

    @ViewBuilder private func dock(drawsBackground: Bool = true) -> some View {
        let size = interaction.layout.viewportSize
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: size, reduceMotion: reduceMotion, edge: interaction.layout.edge)
        // The dock clone inside the launcher is inert artwork, so history browsing stays with the
        // real dock. Both layers share the viewport, and the presentation transform below moves
        // them together, which keeps the track over the glass it measures.
        let timeline = drawsBackground ? interaction.timeline : nil
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
                drawsBackground: drawsBackground,
                primaryAppAction: store.performPrimaryAction,
                openApp: store.open,
                togglePin: store.toggleFavorite,
                dismissError: { store.errorMessage = nil }
            )
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
