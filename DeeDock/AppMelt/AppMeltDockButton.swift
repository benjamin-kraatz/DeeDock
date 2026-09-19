import SwiftUI

/// Each source keeps its own dock identity and icon; either member restores the whole pair.
struct AppMeltDockButton: View {
    let pair: AppMeltPair
    let memberIndex: Int
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @AccessibilityFocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button { interaction.appMelt?.restore(pair) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                available: true, running: !pair.minimized, launching: pair.showsOperationProgress, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation) {
                Image(nsImage: pair.icons[memberIndex]).resizable()
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) {
                        if pair.message != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: size * 0.23, weight: .bold))
                                .background(.regularMaterial, in: .circle)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(pair.busy)
        .contextMenu {
            if let message = pair.message { Text(message) }
            Button(.meltRestore) { interaction.appMelt?.restore(pair) }
            Button(.meltMinimize) { interaction.appMelt?.minimize(pair) }
            Button(.meltClose) { interaction.appMelt?.close(pair) }
            Divider()
            Button(.meltUnpair) { interaction.appMelt?.unpair(pair) }
        }
        .help(pair.title + (pair.message.map { "\n" + String(localized: $0) } ?? ""))
        .accessibilityLabel(Text(verbatim: pair.names[memberIndex] + ", " + pair.title))
        .accessibilityValue(Text(pair.minimized ? .meltMinimized : .meltPaired))
        .accessibilityHint(Text(.meltDockHint))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}
