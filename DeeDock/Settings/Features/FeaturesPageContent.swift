import SwiftUI

/// Opt-in capabilities rather than appearance or placement choices, so every value here is
/// configured once for the whole app and nothing is overridable per display.
struct FeaturesPageContent: View {
    let page: SettingsPage
    let context: SettingsContext

    private var source: SettingsValueSource { context.source() }
    private var locked: Bool { context.isLocked() }

    var body: some View {
        switch page {
        case .shelfAndTrash:
            SettingsCard(title: .settingsShelf, footnote: .settingsShelfHelp) {
                SettingsToggleRow(title: .settingsShowShelf, isOn: source.binding(\.showShelf))
            }
            .disabled(locked)
            SettingsCard(title: .settingsTrash, footnote: .settingsTrashHelp) {
                SettingsToggleRow(title: .settingsShowTrash, isOn: source.binding(\.showTrash))
                SettingsToggleRow(title: .settingsConfirmBeforeEmptyingTrash,
                                  isOn: source.binding(\.confirmBeforeEmptyingTrash))
            }
            .disabled(locked)
        case .capsules:
            SettingsCard(title: .settingsCapsules, footnote: .settingsCapsulesHelp) {
                SettingsToggleRow(title: .settingsShowCapsules, isOn: source.binding(\.showSessionCapsules))
            }
            .disabled(locked)
        case .badges:
            AppBadgesSettingsCard(isOn: source.binding(\.showAppBadges),
                                  windowAccess: context.windowAccess, locked: locked)
            if let coordinator = context.coordinator {
                BadgeMemorySettingsCard(memory: coordinator.badgeMemory, open: { coordinator.showBadgeMemory(digest: true) })
            }
        case .windowPeek:
            // Permissions stay usable on their own page even when unreadable settings block edits.
            WindowPeekSettingsPane(source: source, persistentSettingsDisabled: locked)
        case .focusSessions:
            if let coordinator = context.coordinator {
                FocusSessionSettingsCard(controller: coordinator.focusSession)
                BadgeMemorySettingsCard(memory: coordinator.badgeMemory, open: { coordinator.showBadgeMemory(digest: true) })
            }
        case .actionTiles:
            if let actions = context.coordinator?.actionTiles { ActionTilesSettingsCard(controller: actions) }
            if let destinations = context.coordinator?.fileDestinations {
                LauncherFileDestinationsSettingsCard(store: destinations)
            }
        case .multipleDisplays:
            SettingsCard(title: .secondaryDockTitle, footnote: .secondaryDockHelp) {
                SettingsToggleRow(title: .secondaryDockToggle,
                                  isOn: source.binding(\.secondaryDisplayAppsOnly))
            }
            .disabled(locked)
        case .appSuggestions:
            if let coordinator = context.coordinator {
                LauncherSuggestionsSettingsView(store: coordinator.launcherSuggestions,
                                                applications: coordinator.launcherApplications)
            }
        case .localHistory:
            if let coordinator = context.coordinator {
                DockTimelineSettingsCard(history: coordinator.localHistory,
                                         browse: { coordinator.browseLocalHistory() })
            }
        case .magneticEdges:
            MagneticEdgesSettingsCard(source: source, locked: locked)
        case .permissions:
            PreviewPermissionsSettingsCard(windowAccess: context.windowAccess,
                                           screenCapture: context.screenCapture)
        case .sims:
            if let coordinator = context.coordinator {
                DockSimsSettingsCard(sims: coordinator.sims)
            }
        case .soapBubbles:
            SettingsCard(title: .soapBubblesTitle, footnote: .soapBubblesSettingsHelp) {
                SettingsToggleRow(title: .soapBubblesEnable, subtitle: .soapBubblesEnableHelp,
                                  isOn: source.binding(\.soapBubbleEffects))
            }
            .disabled(locked)
        default:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Soap bubbles, off") {
    SettingsCard(title: .soapBubblesTitle, footnote: .soapBubblesSettingsHelp) {
        SettingsToggleRow(title: .soapBubblesEnable, subtitle: .soapBubblesEnableHelp,
                          isOn: .constant(false))
    }
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Soap bubbles, on") {
    SettingsCard(title: .soapBubblesTitle, footnote: .soapBubblesSettingsHelp) {
        SettingsToggleRow(title: .soapBubblesEnable, subtitle: .soapBubblesEnableHelp,
                          isOn: .constant(true))
    }
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
    .preferredColorScheme(.dark)
}
#endif
