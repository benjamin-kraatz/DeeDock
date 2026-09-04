import SwiftUI

/// Retains the redesigned sidebar, pane previews, cards, and search while adding display scope.
struct DockSettingsView: View {
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore
    let loginItems: LoginItemController
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController
    var coordinator: DockCoordinator? = nil
    @State private var selection: SettingsSelection? = .defaults(.appearance)
    @State private var settingsActive = false
    @State private var searchText = ""
    @State private var displayCategory: SettingsCategory = .appearance

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, searchText: $searchText, profiles: profiles)
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsPane(controller: loginItems)
            case .defaults(let category):
                SettingsDetailView(store: store, category: category, profileError: profiles.errorMessage,
                                   windowAccess: windowAccess, screenCapture: screenCapture)
            case .display(let id):
                SettingsDetailView(store: store, category: displayCategory,
                                   context: SettingsOverrideContext(profiles: profiles, id: id),
                                   profileError: profiles.errorMessage ?? profiles.pinErrors[id], showZone: zoneAction(for: id),
                                   windowAccess: windowAccess, screenCapture: screenCapture,
                                   displayCategory: $displayCategory)
                    .id(id)
            case nil:
                SettingsDetailView(store: store, category: nil)
            }
        }
        .background {
            SettingsWindowLifecycle(closed: {
                coordinator?.zonePreview.stop()
                coordinator?.displayIndicator.stop()
            }, activityChanged: {
                settingsActive = $0
                if $0 {
                    loginItems.refresh()
                    windowAccess.refresh()
                    screenCapture.refresh()
                }
                updateDisplayIndicator(active: $0)
            })
        }
        .onChange(of: profiles.displays) { _, _ in updateDisplayIndicator() }
        .onChange(of: selectedDisplayDockEdge) { _, _ in updateDisplayIndicator() }
        .onChange(of: displayCategory) { _, _ in coordinator?.zonePreview.stop() }
        .onChange(of: selection) { _, _ in
            coordinator?.zonePreview.stop()
            updateDisplayIndicator()
        }
        .onAppear { updateDisplayIndicator() }
        .onChange(of: coordinator?.settingsDisplayRequest, initial: true) { _, requestedID in
            guard let requestedID else { return }
            coordinator?.settingsDisplayRequest = nil
            // Connectivity may have changed between the menu action and scene creation.
            guard profiles.displays.count > 1,
                  profiles.displays.contains(where: { $0.id == requestedID }) else { return }
            searchText = ""
            selection = .display(requestedID)
        }
        .onChange(of: coordinator?.settingsPreviewDisplayRequest, initial: true) { _, requestedID in
            guard let requestedID else { return }
            coordinator?.settingsPreviewDisplayRequest = nil
            searchText = ""
            if profiles.displays.count > 1,
               profiles.displays.contains(where: { $0.id == requestedID }) {
                displayCategory = .previews
                selection = .display(requestedID)
            } else {
                selection = .defaults(.previews)
            }
        }
        .onDisappear {
            settingsActive = false
            coordinator?.zonePreview.stop()
            coordinator?.displayIndicator.stop()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, idealWidth: 820, minHeight: 540, idealHeight: 650)
        .onChange(of: profiles.document.profiles.keys.sorted()) { _, ids in
            if case .display(let id) = selection, !ids.contains(id) { selection = .defaults(.appearance) }
        }
    }
    private func updateDisplayIndicator(active: Bool? = nil) {
        let id: String?
        if case .display(let selectedID) = selection { id = selectedID } else { id = nil }
        coordinator?.displayIndicator.update(
            selectedID: id,
            displays: profiles.displays,
            dockEdge: selectedDisplayDockEdge,
            settingsActive: active ?? settingsActive
        )
    }

    private var selectedDisplayDockEdge: DockEdge? {
        guard case .display(let id) = selection else { return nil }
        return profiles.effectiveSettings(for: id).edge
    }

    private func zoneAction(for id: String) -> (() -> Void)? {
        guard let coordinator, coordinator.enabledDisplays.contains(where: { $0.id == id }) else { return nil }
        return { coordinator.showZone(for: id) }
    }
}

#if DEBUG
#Preview("Multiple displays") {
    let profiles = DisplaySettingsPreview.make()
    DockSettingsView(store: profiles.defaults, profiles: profiles, loginItems: LoginItemPreview.controller(),
                     windowAccess: WindowAccessPreview.controller(), screenCapture: ScreenCaptureAccessPreview.controller())
}
#Preview("Multiple displays — dark") {
    let profiles = DisplaySettingsPreview.make()
    DockSettingsView(store: profiles.defaults, profiles: profiles, loginItems: LoginItemPreview.controller(),
                     windowAccess: WindowAccessPreview.controller(), screenCapture: ScreenCaptureAccessPreview.controller()).preferredColorScheme(.dark)
}
#endif
