import SwiftUI

/// Permanent utility tile participates in the dock's shared geometry and keyboard navigation.
///
/// Its position comes from ``LauncherDockPosition``. Dragging it, or the VoiceOver move actions
/// added by ``DockUtilityMoveModifier``, change that position.
struct DockLauncherButton: View {
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private
        var reduceTransparency
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        Button {
            interaction.openLauncher?()
        } label: {
            DockIconPresentation(
                size: size,
                edge: interaction.layout.edge,
                available: true,
                running: false,
                launching: false,
                keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(
                    settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction,
                    reduceTransparency: reduceTransparency
                ).icons,
                artworkAnimation: interaction.idleFade.animation
            ) {
                LauncherTileArtwork(size: size)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.launcherTitle))
        .accessibilityHint(Text(.launcherTileHint))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}

#Preview {
    DockLauncherButton(
        size: 64,
        selected: false,
        interaction: DockInteraction(),
        accessibilityFocus: { _ in }
    )
    .padding()
}
