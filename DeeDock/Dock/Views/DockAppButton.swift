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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var artworkOpacity: Double {
        guard let fade = interaction?.idleFade else { return 1 }
        return DockAppearanceOpacity(settings: fade.settings, idleFraction: fade.fraction,
                                     reduceTransparency: reduceTransparency).icons
    }
    /// Stable per-application variation for Stardust sparkle sites.
    private var indicatorVariant: DockIndicatorVariant {
        DockIndicatorVariant(identity: item.id)
    }
    /// A dock nobody can see, or one that has already faded out, schedules no frames.
    private var indicatorAnimated: Bool { 
        guard let interaction else { return false }
        return interaction.animateIndicators && interaction.exposesContent && interaction.idleFade.fraction == 0
    }
    @Environment(\.openWindow) private var openWindow
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @State private var accessibilityWindows: [ApplicationWindowSummary] = []
    @State private var accessibilityDiscoveryID: UUID?
    /// Captured when VoiceOver focuses the button. `.accessibilityActions` builds its content during
    /// every `body` pass, and a live process snapshot there would scan running apps on each pointer move.
    @State private var accessibilityAllHidden = false

    private var pinWeatherSample: PinWeatherSample? {
        guard item.isFavorite, let weather = interaction?.pinWeather else { return nil }
        return weather.sample(for: item.id)
    }

    private var badgeKey: String { DockBadgePath.key(for: item.resolvedURL ?? item.reference.url) }

    var body: some View {
        // One lookup per pass. `DockBadgePath` caches the installation key.
        let badgeKey = self.badgeKey
        let badgeLabel = item.isAvailable ? interaction?.badges?.labels[badgeKey] : nil
        let badgeAttention = interaction?.badges.map { $0.attention.isNew(key: badgeKey, label: badgeLabel) }
        let lineIcon = interaction?.lineIcon(for: item.reference, artwork: item.icon)
        // Clicking the tile acknowledges its badge, which clears a line tile's ring. Activation
        // does too, but an app that is already frontmost does not activate again.
        let activate = {
            interaction?.badges?.attention.acknowledge(key: badgeKey, label: badgeLabel, via: .dockClick)
            primaryAction()
        }
        Button(action: activate) {
            DockIconPresentation(icon: item.icon, size: size, edge: interaction?.layout.edge ?? .bottom,
                                 available: item.isAvailable, running: item.isRunning,
                                 launching: isLaunching, keyboardSelected: isKeyboardSelected,
                                 runningIndicatorStyle: interaction?.runningIndicatorStyle ?? .dot,
                                 indicatorVariant: indicatorVariant, indicatorAnimated: indicatorAnimated,
                                 artworkOpacity: artworkOpacity, artworkAnimation: interaction?.idleFade.animation,
                                 badgeLabel: badgeLabel,
                                 badgeStyle: interaction?.showAppBadgeCounts == true ? .count : .dot,
                                 badgeAttention: badgeAttention,
                                 launchAnimation: interaction?.launchAnimation ?? DockSettings.defaults.launchAnimation,
                                 launchRequest: interaction?.applicationCatalog?.launchAnimationRequests[item.id],
                                 launchMotionEnabled: interaction.map { $0.exposesContent && $0.idleFade.fraction == 0 } ?? true,
                                 lineIcon: lineIcon)
                .environment(\.pinWeatherSample, pinWeatherSample)
                .overlay {
                    if interaction?.documentTargetID == item.id {
                        DockDocumentHighlight(emphasized: interaction?.springEmphasized == true)
                            .allowsHitTesting(false)
                    }
                    if let interaction, let sims = interaction.sims,
                       let state = sims.pinState(for: item.id, isFavorite: item.isFavorite) {
                        DockSimsOverlay(state: state, size: size, edge: interaction.layout.edge,
                                        artworkOpacity: artworkOpacity, animated: indicatorAnimated)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    if AppDockPresence.representsCurrentApplication(item.reference),
                       let awareness = interaction?.updateAwareness, awareness.showsDockPip {
                        UpdateAwarenessPip(reduceMotion: reduceMotion, installed: !awareness.showsIndicators)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(2)
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
                    primaryAction: activate,
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
                    openWindow.openDockSettings()
                },
                tracking: menuTracking
            )
        }
        .overlay(alignment: .topTrailing) {
            // A line tile's ring has no corner mark to click; Badge details stays in its menu.
            if badgeLabel != nil, lineIcon == nil, interaction?.openBadgeMemory != nil {
                Button { interaction?.openBadgeMemory?(item) } label: {
                    Color.clear.frame(width: max(20, size * 0.85), height: max(20, size * 0.35))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Match the upright icon origin, accounting for the edge's indicator strip.
                .padding(.top, interaction?.layout.edge == .top ? DockGeometry.indicatorAreaDepth : 0)
                .padding(.trailing, interaction?.layout.edge == .right ? DockGeometry.indicatorAreaDepth : 0)
                .help(.badgeMemoryDetails)
                .accessibilityLabel(Text(.badgeMemoryDetails))
            }
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
        .accessibilityValue(accessibilityStatus(badgeLabel: badgeLabel,
                                                newBadge: lineIcon != nil && badgeAttention == true))
        .accessibilityHint(Text(.appOpenHint))
        .accessibilityAction(
            named: Text(item.isFavorite ? .actionUnpin : .actionPin),
            { Analytics.performing(.voiceOver, togglePin) }
        )
        .accessibilityActions {
            if interaction?.openBadgeMemory != nil {
                Button(.badgeMemoryDetails) { Analytics.performing(.voiceOver) { interaction?.openBadgeMemory?(item) } }
            }
            if item.isAvailable {
                Button(.actionOpenFiles) { Analytics.performing(.voiceOver) { interaction?.openFiles?(item) } }
                Button(.applicationMenuShowInFinder) { menuAction(.showInFinder) }
            }
            if item.isRunning {
                let allHidden = accessibilityAllHidden
                Button(allHidden ? .applicationMenuShow : .applicationMenuHide) {
                    menuAction(.setHidden(!allHidden))
                    accessibilityAllHidden = !allHidden
                }
                Button(.applicationMenuBringAllToFront) { menuAction(.bringAllToFront) }
                Button(.applicationMenuQuit) { menuAction(.quit) }
            }
            ForEach(accessibilityWindows) { window in
                Button(.applicationMenuOpenWindow(
                    title: ApplicationContextMenuProjection.windowTitle(
                        window,
                        untitled: String(localized: .applicationMenuUntitledWindow)
                    )
                )) {
                    accessibilityDiscoveryID = nil
                    menuAction(.selectWindow(window.token))
                }
            }
            if item.isFavorite, interaction?.sims?.isEnabled == true {
                Button(.simsFeed) { interaction?.sims?.care(.feed, pinID: item.id) }
                Button(.simsCheer) { interaction?.sims?.care(.cheer, pinID: item.id) }
                Button(.simsSettle) { interaction?.sims?.care(.settle, pinID: item.id) }
            }
            if item.isFavorite {
                Button {
                    Analytics.performing(.voiceOver) { interaction?.movePin?(item.id, -1) }
                } label: {
                    Text(interaction?.layout.edge.isVertical == true ? .actionMoveUp : .actionMoveLeft)
                }
                .disabled(interaction?.canMovePin?(item.id, -1) != true)
                Button {
                    Analytics.performing(.voiceOver) { interaction?.movePin?(item.id, 1) }
                } label: {
                    Text(interaction?.layout.edge.isVertical == true ? .actionMoveDown : .actionMoveRight)
                }
                .disabled(interaction?.canMovePin?(item.id, 1) != true)
            }
            ForEach(interaction?.pinDestinations ?? []) { destination in
                Button {
                    Analytics.performing(.voiceOver) { interaction?.copyPin?(.application(item.reference), destination.id) }
                } label: {
                    Text(.actionPinOnDisplayName(display: destination.name))
                }
            }
        }
        .modifier(QuarantineItemModifier(id: item.id, url: item.resolvedURL ?? item.reference.url,
                                         name: item.reference.name, eligible: item.isFavorite))
    }

    /// A context-menu action reached through VoiceOver's actions rotor.
    private func menuAction(_ action: ApplicationMenuAction) {
        Analytics.performing(.voiceOver) { interaction?.performApplicationMenuAction?(action, item) }
    }

    /// - Parameter newBadge: True when a line tile's ring marks the badge as news, so VoiceOver says so too.
    private func accessibilityStatus(badgeLabel: String?, newBadge: Bool) -> Text {
        let status = String(localized: item.isAvailable
            ? (item.isRunning ? LocalizedStringResource.appStatusRunning : .appStatusNotRunning)
            : .appStatusUnavailable)
        let mood = interaction?.sims?.pinState(for: item.id, isFavorite: item.isFavorite).map {
            String(localized: $0.mood(at: .now).title)
        }
        if let badgeLabel {
            let badge = String(localized: newBadge
                ? .appBadgeNewAccessibility(status: status, badge: badgeLabel)
                : .appBadgeAccessibility(status: status, badge: badgeLabel))
            if let mood {
                return Text(verbatim: "\(badge), \(String(localized: .simsMoodAccessibility(mood: mood)))")
            }
            return Text(verbatim: badge)
        }
        if let mood {
            return Text(verbatim: "\(status), \(String(localized: .simsMoodAccessibility(mood: mood)))")
        }
        return Text(verbatim: status)
    }

    private func discoverAccessibilityWindows() {
        let snapshot = interaction?.applicationMenuSnapshot?(item)
        accessibilityAllHidden = snapshot?.allProcessesHidden == true
        guard accessibilityDiscoveryID == nil, let snapshot, snapshot.windowState == .loading else {
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
