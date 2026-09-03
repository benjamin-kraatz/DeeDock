import SwiftUI

/// An app icon with running, launch-progress, selection, and accessibility states.
///
/// Its closures express user intent; this component never invokes workspace APIs itself.
struct DockAppButton: View {
    let item: DockItem
    /// Current magnified icon dimension in logical points; indicator space is additional.
    let size: CGFloat
    let isLaunching: Bool
    /// Set by Focus Dock navigation; does not identify the foreground application.
    let isKeyboardSelected: Bool
    let primaryAction: () -> Void
    let open: () -> Void
    let togglePin: () -> Void

    var interaction: DockInteraction? = nil
    var menuTracking: (Bool) -> Void = { _ in }
    var accessibilityFocus: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var artworkOpacity: Double {
        guard let fade = interaction?.idleFade else { return 1 }
        return DockAppearanceOpacity(settings: fade.settings, idleFraction: fade.fraction,
                                     reduceTransparency: reduceTransparency).icons
    }
    @Environment(\.openSettings) private var openSettings
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        Button(action: primaryAction) {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction?.layout.edge ?? .bottom,
                                 available: item.isAvailable, running: item.isRunning,
                                 launching: isLaunching, keyboardSelected: isKeyboardSelected,
                                 runningIndicatorStyle: interaction?.runningIndicatorStyle ?? .dot,
                                 artworkOpacity: artworkOpacity, artworkAnimation: interaction?.idleFade.animation)
                .overlay {
                    if interaction?.documentTargetID == item.id {
                        DockDocumentHighlight(emphasized: interaction?.springEmphasized == true)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .overlay {
            if let interaction, let begin = interaction.beginDrag {
                DockDragSourceView(
                    item: item,
                    enabled: !isLaunching,
                    primaryAction: primaryAction,
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
            if item.isAvailable {
                Button(.actionOpenFiles) { interaction?.openFiles?(item) }
            }
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
                isKeyboardSelected: true,
                primaryAction: {},
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[3],
                size: 48,
                isLaunching: false,
                isKeyboardSelected: false,
                primaryAction: {},
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[1],
                size: 48,
                isLaunching: true,
                isKeyboardSelected: false,
                primaryAction: {},
                open: {},
                togglePin: {}
            )
            DockAppButton(
                item: DockPreviewData.items[2],
                size: 48,
                isLaunching: false,
                isKeyboardSelected: false,
                primaryAction: {},
                open: {},
                togglePin: {}
            )
        }
        .padding(20)
    }
#endif
