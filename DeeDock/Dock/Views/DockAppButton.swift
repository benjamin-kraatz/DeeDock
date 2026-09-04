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
    /// Stable per-application shader variation, tinted by the icon's own dominant hue.
    /// `DockIconAccent` caches by identity, so reading it from the body stays cheap.
    private var indicatorVariant: DockIndicatorVariant {
        DockIndicatorVariant(identity: item.id,
                             accent: DockIconAccent.accent(for: item.icon, identity: item.id))
    }
    /// A dock nobody can see, or one that has already faded out, schedules no frames.
    private var indicatorAnimated: Bool { 
        guard let interaction else { return false }
        return interaction.animateIndicators && interaction.exposesContent && interaction.idleFade.fraction == 0
    }
    @Environment(\.openSettings) private var openSettings
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @State private var accessibilityWindows: [ApplicationWindowSummary] = []
    @State private var accessibilityDiscoveryID: UUID?

    var body: some View {
        Button(action: primaryAction) {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction?.layout.edge ?? .bottom,
                                 available: item.isAvailable, running: item.isRunning,
                                 launching: isLaunching, keyboardSelected: isKeyboardSelected,
                                 runningIndicatorStyle: interaction?.runningIndicatorStyle ?? .dot,
                                 indicatorVariant: indicatorVariant, indicatorAnimated: indicatorAnimated,
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
            if focused { discoverAccessibilityWindows() }
            else { cancelAccessibilityWindowDiscovery() }
        }
        .onDisappear {
            accessibilityFocus(false)
            cancelAccessibilityWindowDiscovery()
        }
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
                Button(.applicationMenuShowInFinder) { interaction?.performApplicationMenuAction?(.showInFinder, item) }
            }
            if item.isRunning {
                let allHidden = interaction?.applicationMenuSnapshot?(item).allProcessesHidden == true
                Button(allHidden ? .applicationMenuShow : .applicationMenuHide) {
                    interaction?.performApplicationMenuAction?(.setHidden(!allHidden), item)
                }
                Button(.applicationMenuBringAllToFront) { interaction?.performApplicationMenuAction?(.bringAllToFront, item) }
                Button(.applicationMenuQuit) { interaction?.performApplicationMenuAction?(.quit, item) }
            }
            ForEach(accessibilityWindows) { window in
                Button(.applicationMenuOpenWindow(
                    title: ApplicationContextMenuProjection.windowTitle(
                        window,
                        untitled: String(localized: .applicationMenuUntitledWindow)
                    )
                )) {
                    accessibilityDiscoveryID = nil
                    interaction?.performApplicationMenuAction?(.selectWindow(window.token), item)
                }
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
                    interaction?.copyPin?(.application(item.reference), destination.id)
                } label: {
                    Text(.actionPinOnDisplayName(display: destination.name))
                }
            }
        }
    }

    private func discoverAccessibilityWindows() {
        guard accessibilityDiscoveryID == nil,
              let snapshot = interaction?.applicationMenuSnapshot?(item),
              snapshot.windowState == .loading else {
            accessibilityWindows = []
            return
        }
        accessibilityDiscoveryID = interaction?.beginApplicationWindowDiscovery?(item, snapshot) { state in
            guard case .loaded(let windows) = state else {
                accessibilityWindows = []
                accessibilityDiscoveryID = nil
                return
            }
            accessibilityWindows = windows
        }
    }

    private func cancelAccessibilityWindowDiscovery() {
        if let accessibilityDiscoveryID {
            interaction?.cancelApplicationWindowDiscovery?(accessibilityDiscoveryID)
        }
        accessibilityDiscoveryID = nil
        accessibilityWindows = []
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
