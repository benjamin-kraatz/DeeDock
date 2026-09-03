import SwiftUI

/// An app icon with running, launch-progress, selection, and accessibility states.
///
/// `open` and `togglePin` express user intent; this component never invokes workspace APIs itself.
struct DockAppButton: View {
    let item: DockItem
    /// Current magnified icon dimension in logical points; indicator space is additional.
    let size: CGFloat
    let isLaunching: Bool
    let isSelected: Bool
    let open: () -> Void
    let togglePin: () -> Void

    var interaction: DockInteraction? = nil
    var menuTracking: (Bool) -> Void = { _ in }
    var accessibilityFocus: (Bool) -> Void = { _ in }
    @Environment(\.openSettings) private var openSettings
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        Button(action: open) {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction?.layout.edge ?? .bottom,
                                 available: item.isAvailable, running: item.isRunning,
                                 launching: isLaunching, selected: isSelected)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .overlay {
            if let interaction, let begin = interaction.beginDrag {
                DockDragSourceView(
                    item: item,
                    enabled: !isLaunching,
                    open: open,
                    begin: begin,
                    tracking: { interaction.sourceTrackingChanged?($0) }
                )
            }
        }
        .overlay {
            DockContextMenuBridge(
                item: item,
                open: open,
                togglePin: togglePin,
                interaction: interaction,
                openSettings: {
                    interaction?.prepareSettings?()
                    NSApp.activate()
                    openSettings()
                },
                tracking: menuTracking
            )
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in
            accessibilityFocus(focused)
        }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(verbatim: item.reference.name))
        .accessibilityValue(
            Text(
                item.isAvailable
                    ? (item.isRunning
                        ? .appStatusRunning : .appStatusUnavailable)
                    : .appStatusUnavailable
            )
        )
        .accessibilityHint(Text(.appOpenHint))
        .accessibilityAction(
            named: Text(item.isFavorite ? .actionUnpin : .actionPin),
            togglePin
        )
        .accessibilityActions {
            if item.isFavorite {
                Button {
                    interaction?.movePin?(item.id, -1)
                } label: {
                    Text(interaction?.layout.edge.isVertical == true ? .actionMoveUp : .actionMoveLeft)
                }
                .disabled(interaction?.canMovePin?(item.id, -1) != true)
                Button {
                    interaction?.movePin?(item.id, 1)
                } label: {
                    Text(interaction?.layout.edge.isVertical == true ? .actionMoveDown : .actionMoveRight)
                }
                .disabled(interaction?.canMovePin?(item.id, 1) != true)
            }
            ForEach(interaction?.pinDestinations ?? []) { destination in
                Button {
                    interaction?.copyPin?(item.reference, destination.id)
                } label: {
                    Text(.actionPinOnDisplayName(display: destination.name))
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Selected, running, launching, unavailable") {
        HStack(spacing: 20) {
            DockAppButton(
                item: DockPreviewData.items[0],
                size: 48,
                isLaunching: false,
                isSelected: true,
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[3],
                size: 48,
                isLaunching: false,
                isSelected: false,
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[1],
                size: 48,
                isLaunching: true,
                isSelected: false,
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[2],
                size: 48,
                isLaunching: false,
                isSelected: false,
                open: {},
                togglePin: {}
            )
        }
        .padding(20)
    }
#endif
