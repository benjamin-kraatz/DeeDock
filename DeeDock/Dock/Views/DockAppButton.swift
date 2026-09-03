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
            VStack(spacing: 6) {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .opacity(item.isAvailable ? 1 : 0.4)
                    .overlay {
                        if isLaunching {
                            Circle().fill(.black.opacity(0.14))
                        }
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .overlay {
                        if isLaunching {
                            ProgressView().controlSize(.small)
                                .padding(8)
                                .glassEffect(.clear)
                        }
                    }
                if !isSelected {
                    Circle().fill(.primary.opacity(item.isRunning ? 0.8 : 0))
                        .frame(width: 4, height: 4)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(.primary)
                        .frame(width: 16, height: 4)
                }
            }
            .frame(width: size, height: size + 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .overlay {
            if let interaction, let begin = interaction.beginDrag {
                DockDragSourceView(item: item, enabled: !isLaunching, open: open, begin: begin,
                                   tracking: { interaction.sourceTrackingChanged?($0) })
            }
        }
        .overlay {
            DockContextMenuBridge(
                item: item,
                open: open,
                togglePin: togglePin,
                interaction: interaction,
                openSettings: {
                    NSApp.activate()
                    openSettings()
                },
                tracking: menuTracking
            )
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(verbatim: item.reference.name))
        .accessibilityValue(Text(item.isAvailable ? (item.isRunning ? .appStatusRunning : .appStatusUnavailable) : .appStatusUnavailable))
        .accessibilityHint(Text(.appOpenHint))
        .accessibilityAction(named: Text(item.isFavorite ? .actionUnpin : .actionPin), togglePin)
        .accessibilityActions {
            if item.isFavorite {
                Button { interaction?.movePin?(item.id, -1) } label: { Text(.actionMoveLeft) }
                    .disabled(interaction?.canMovePin?(item.id, -1) != true)
                Button { interaction?.movePin?(item.id, 1) } label: { Text(.actionMoveRight) }
                    .disabled(interaction?.canMovePin?(item.id, 1) != true)
            }
            ForEach(interaction?.pinDestinations ?? []) { destination in
                Button { interaction?.copyPin?(item.reference, destination.id) } label: {
                    Text(.actionPinOnDisplayName(display: destination.name))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Running, launching, unavailable") {
    HStack(spacing: 20) {
        DockAppButton(item: DockPreviewData.items[0], size: 48, isLaunching: false, isSelected: true,
                      open: {}, togglePin: {})
        DockAppButton(item: DockPreviewData.items[1], size: 48, isLaunching: true, isSelected: false,
                      open: {}, togglePin: {})
        DockAppButton(item: DockPreviewData.items[2], size: 48, isLaunching: false, isSelected: false,
                      open: {}, togglePin: {})
    }
    .padding(20)
}
#endif
