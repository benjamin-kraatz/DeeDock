import SwiftUI

/// One shortcut tile with native icon framing and execution feedback shared across displays.
struct DockActionButton: View {
    let item: ActionDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        Button { interaction.actionTiles?.run(item.tile.id) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: false, launching: false,
                                 keyboardSelected: selected,
                                 artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                                    idleFraction: interaction.idleFade.fraction,
                                    reduceTransparency: reduceTransparency).icons,
                                 artworkAnimation: interaction.idleFade.animation) {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.23).fill(.purple.gradient)
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.48)).foregroundStyle(.white)
                }
                .overlay(alignment: .bottomTrailing) {
                    statusBadge.padding(2).background(.regularMaterial, in: .circle)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(item.status.busy)
        .help(item.tile.name + " · " + item.status.title)
        .accessibilityLabel(Text(verbatim: item.tile.name))
        .accessibilityValue(Text(verbatim: item.status.title))
        .accessibilityHint(Text(.actionsTileHint))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.status {
        case .idle: EmptyView()
        case .running:
            if interaction.exposesContent { ProgressView().controlSize(.mini) }
            else { Image(systemName: "hourglass") }
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }
}
