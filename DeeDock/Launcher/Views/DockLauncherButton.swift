import SwiftUI

private let iconSizeFactor: CGFloat = 0.85

/// Permanent utility tile participates in the dock's shared geometry and keyboard navigation.
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
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size * iconSizeFactor, height: size * iconSizeFactor)
                    .background(
                        LinearGradient(
                            colors: [.indigo, .indigo.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: .rect(cornerRadius: size * 0.26)
                    )
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
