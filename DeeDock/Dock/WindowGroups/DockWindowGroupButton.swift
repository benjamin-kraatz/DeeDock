import SwiftUI

/// Window count and disclosure beside the owning app; this button never launches the app.
struct DockWindowGroupButton: View {
    let group: DockWindowGroup
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    var accessibilityFocus: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        Button { interaction.toggleWindowGroup?(group.app.id) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge, available: true,
                running: false, launching: false, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation) {
                VStack(spacing: 2) {
                    Image(systemName: group.expanded ? "rectangle.stack.fill" : "rectangle.stack")
                        .font(.system(size: size * 0.32))
                    HStack(spacing: 3) {
                        Text(group.count, format: .number)
                        Image(systemName: group.expanded ? "chevron.down" : "chevron.forward")
                    }.font(.system(size: max(10, size * 0.2), weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(interaction.windowGroupsExpanded)
        .accessibilityLabel(Text(group.title))
        .accessibilityValue(Text(group.count, format: .number))
        .accessibilityHint(Text(interaction.windowGroupsExpanded ? .windowGroupsPinnedHint : .windowGroupsDisclosureHint))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}
