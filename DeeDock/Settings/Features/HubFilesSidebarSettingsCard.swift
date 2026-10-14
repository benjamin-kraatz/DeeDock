import SwiftUI

/// Settings → DOKK Hub: the Files sidebar's built-in places.
///
/// Places removed from the sidebar (right-click → Remove from Sidebar, or dragged out) come back
/// here, each in its default position. Added folders stay where they are. The same command sits
/// in the context menu of the sidebar's Favorites header.
struct HubFilesSidebarSettingsCard: View {
    let sidebar: HubFilesSidebarModel

    private var missing: [HubFilesPlace] { sidebar.store.missingPlaces }

    var body: some View {
        SettingsCard(title: .settingsHubSidebarTitle, footnote: .settingsHubSidebarHelp) {
            SettingsRow(title: .settingsHubSidebarPlaces, subtitle: status) {
                Button(.hubFilesSidebarRestorePlaces) {
                    sidebar.restoreDefaultPlaces(method: .settings)
                }
                .disabled(missing.isEmpty)
            }
        }
    }

    /// "All places are shown", or which ones are hidden.
    private var status: LocalizedStringResource {
        guard !missing.isEmpty else { return .settingsHubSidebarAllPlacesShown }
        let names = missing.map { $0.title(home: sidebar.store.home) }.formatted(.list(type: .and))
        return .settingsHubSidebarPlacesRemoved(names)
    }
}
