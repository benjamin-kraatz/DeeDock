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
        case .windowPeek:
            // Permissions stay usable on their own page even when unreadable settings block edits.
            WindowPeekSettingsPane(source: source, persistentSettingsDisabled: locked)
        case .focusSessions:
            if let focus = context.coordinator?.focusSession { FocusSessionSettingsCard(controller: focus) }
        case .actionTiles:
            if let actions = context.coordinator?.actionTiles { ActionTilesSettingsCard(controller: actions) }
        case .multipleDisplays:
            SettingsCard(title: .secondaryDockTitle, footnote: .secondaryDockHelp) {
                SettingsToggleRow(title: .secondaryDockToggle,
                                  isOn: source.binding(\.secondaryDisplayAppsOnly))
            }
            .disabled(locked)
        case .permissions:
            PreviewPermissionsSettingsCard(windowAccess: context.windowAccess,
                                           screenCapture: context.screenCapture)
        default:
            EmptyView()
        }
    }
}
