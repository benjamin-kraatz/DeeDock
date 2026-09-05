import SwiftUI

/// A title-bearing window tile. Full titles use the Dock's shared tooltip and VoiceOver path.
struct DockWindowButton: View {
    let item: DockWindowItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    var accessibilityFocus: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        Button { interaction.selectDockWindow?(item) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge, available: true,
                running: false, launching: false, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation) {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Image(nsImage: item.app.icon).resizable().frame(width: size * 0.25, height: size * 0.25)
                        Spacer(minLength: 0)
                        Image(systemName: "macwindow").font(.system(size: size * 0.19)).foregroundStyle(.secondary)
                    }
                    Text(verbatim: item.title).font(.system(size: max(9, size * 0.18), weight: .medium))
                        .lineLimit(2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .padding(size * 0.1)
                .frame(width: size, height: size)
                .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                            in: .rect(cornerRadius: size * 0.16))
                .overlay { RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(.primary.opacity(0.18), lineWidth: 0.5) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.windowGroupsWindowLabel(item.app.reference.name, item.title)))
        .accessibilityHint(Text(.windowGroupsSelectHint))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}

#if DEBUG
#Preview("Window title, long title, keyboard selection") {
    HStack {
        ForEach(["Downloads", "Project notes and customer correspondence"], id: \.self) { title in
            DockWindowButton(item: DockWindowItem(window: DockWindowSnapshot(id: 42, processIdentifier: 1,
                applicationID: "com.apple.finder", displayID: 1, title: title, frame: .zero),
                app: DockPreviewData.items[0]), size: 64, selected: title == "Downloads", interaction: DockInteraction())
        }
    }.padding(20)
}
#endif
