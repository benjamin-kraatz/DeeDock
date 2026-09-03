import SwiftUI

struct DockFolderButton: View {
    let item: FolderDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var primaryAction: () -> Void { { interaction.openFolder?(item, false) } }
    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button(action: primaryAction) {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction.layout.edge,
                                 available: item.isAvailable, running: false, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: max(10, size * 0.22), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4).background(.tint, in: Circle())
                        .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                        .offset(x: -2, y: -DockGeometry.indicatorAreaDepth - 2)
                        .animation(interaction.idleFade.animation) { $0.opacity(artworkOpacity) }
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            if let begin = interaction.beginFolderDrag {
                DockFolderDragSourceView(item: item, primaryAction: primaryAction, begin: begin,
                                         tracking: { interaction.sourceTrackingChanged?($0) })
            }
        }
        .overlay {
            FolderContextMenuBridge(item: item, interaction: interaction, openSettings: {
                interaction.prepareSettings?(); NSApp.activate(); openSettings()
            }, tracking: menuTracking)
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(verbatim: item.reference.name))
        .accessibilityValue(Text(.folderStackAccessibilityValue))
        .accessibilityHint(Text(.folderStackDockHint))
        .accessibilityActions {
            Button(.folderStackOpen) { primaryAction() }
            if item.isAvailable { Button(.folderStackShowInFinder) { interaction.revealFolder?(item) } }
            Button(.actionUnpin) { interaction.removePin?(item.id) }
            Button(item.reference.presentation == .grid ? .folderStackUseList : .folderStackUseGrid) {
                interaction.setFolderPresentation?(item.reference.id, item.reference.presentation == .grid ? .list : .grid)
            }
            Button {
                interaction.movePin?(item.id, -1)
            } label: {
                Text(interaction.layout.edge.isVertical ? .actionMoveUp : .actionMoveLeft)
            }
            .disabled(interaction.canMovePin?(item.id, -1) != true)
            Button {
                interaction.movePin?(item.id, 1)
            } label: {
                Text(interaction.layout.edge.isVertical ? .actionMoveDown : .actionMoveRight)
            }
            .disabled(interaction.canMovePin?(item.id, 1) != true)
            ForEach(interaction.pinDestinations) { destination in
                Button {
                    interaction.copyPin?(.folder(item.reference), destination.id)
                } label: {
                    Text(.actionPinOnDisplayName(display: destination.name))
                }
            }
        }
    }
}
