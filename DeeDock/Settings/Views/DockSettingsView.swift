import SwiftUI

/// Sidebar sections with a native navigation stack for each section’s pages.
struct DockSettingsView: View {
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore
    let loginItems: LoginItemController
    let menuBarIcon: MenuBarIconController
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController
    var coordinator: DockCoordinator? = nil
    @State private var selection: SettingsSection? = .dock
    /// An empty path shows the selected section’s overview.
    @State private var path: [SettingsPage] = []
    @State private var settingsActive = false
    @State private var searchText = ""

    private var context: SettingsContext {
        SettingsContext(store: store, profiles: profiles, loginItems: loginItems, menuBarIcon: menuBarIcon,
                        windowAccess: windowAccess, screenCapture: screenCapture, coordinator: coordinator)
    }

    /// The display being edited, when the sidebar has one selected.
    private var override: SettingsOverrideContext? {
        guard case .display(let id) = selection else { return nil }
        return SettingsOverrideContext(profiles: profiles, id: id)
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: Binding(get: { selection }, set: {
                path = []
                selection = $0
            }), searchText: $searchText, profiles: profiles)
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
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
        .onChange(of: path) { _, _ in coordinator?.zonePreview.stop() }
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
            select(.display(requestedID))
        }
        .onChange(of: coordinator?.settingsModesRequest, initial: true) { _, requested in
            guard requested == true else { return }
            coordinator?.settingsModesRequest = false
            select(.modes)
        }
        .onChange(of: coordinator?.settingsFeaturesRequest, initial: true) { _, requested in
            guard requested == true else { return }
            coordinator?.settingsFeaturesRequest = false
            // Window Peek and its permissions are app-wide, so there is no display to select.
            select(.features, page: .windowPeek)
        }
        .onDisappear {
            settingsActive = false
            coordinator?.zonePreview.stop()
            coordinator?.displayIndicator.stop()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, idealWidth: 820, minHeight: 540, idealHeight: 650)
        .onChange(of: profiles.document.profiles.keys.sorted()) { _, ids in
            if case .display(let id) = selection, !ids.contains(id) { select(.dock) }
        }
    }

    private var detail: some View {
        NavigationStack(path: $path) {
            overview
                .navigationDestination(for: SettingsPage.self) { page in
                    SettingsPageView(page: page, context: context, override: override,
                                     showZone: override.flatMap { zoneAction(for: $0.id) })
                }
        }
    }

    @ViewBuilder private var overview: some View {
        switch selection {
        case .general:
            SettingsOverviewView(section: .general, open: open)
        case .features:
            SettingsOverviewView(section: .features, isAvailable: isAvailable, open: open)
        case .dock:
            SettingsOverviewView(section: .dock, open: open)
        case .modes:
            DockModesSettingsPane(store: profiles.modes,
                                  activateMode: { coordinator?.activateMode($0) ?? profiles.modes.activate($0) },
                                  deleteMode: { coordinator?.deleteMode($0) ?? profiles.modes.delete($0) },
                                  startFocus: { coordinator?.startFocus($0) }, canStartFocus: coordinator?.canStartFocus == true)
        case .display(let id):
            displayOverview(SettingsOverrideContext(profiles: profiles, id: id)).id(id)
        case nil:
            ContentUnavailableView {
                Label { Text(.settingsSelectSection) } icon: { Image(systemName: "slider.horizontal.3") }
            }
        }
    }

    private func displayOverview(_ context: SettingsOverrideContext) -> some View {
        let name = context.profiles.document.profiles[context.id]?.name
        return SettingsOverviewView(section: .display(context.id),
                                    title: name.map { Text(verbatim: $0) } ?? Text(.displayUnnamed),
                                    open: open) {
            DisplaySettingsHeader(context: context)
        }
    }

    private func open(_ page: SettingsPage) { path.append(page) }

    /// A page the build or this machine cannot offer is left out of its overview entirely.
    private func isAvailable(_ page: SettingsPage) -> Bool {
        switch page {
        case .focusSessions: coordinator?.focusSession != nil
        case .actionTiles: coordinator?.actionTiles != nil
        default: true
        }
    }

    /// General and Modes own no dock preferences, so they carry no reset action.
    @ViewBuilder private var footer: some View {
        switch selection {
        case .dock, .features, .display:
            SettingsFooterBar(errorMessage: context.errorMessage(override),
                              resetTitle: override == nil ? .settingsRestoreDefaults : .displayUseDefaults,
                              resetDisabled: override != nil && profiles.requiresReset,
                              restoreDefaults: restoreDefaults)
        default:
            EmptyView()
        }
    }

    private func restoreDefaults() {
        if let override { profiles.useDefaults(for: override.id) }
        else {
            store.restoreDefaults()
            profiles.restoreDefaultVisibility()
        }
    }

    /// A request from outside the window always lands where it was asked for, never mid-navigation.
    private func select(_ section: SettingsSection, page: SettingsPage? = nil) {
        searchText = ""
        selection = section
        // Set both together so external requests can open a specific destination.
        path = page.map { [$0] } ?? []
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
                     menuBarIcon: MenuBarIconController(defaults: UserDefaults(suiteName: "SettingsMenuBarPreview") ?? .standard),
                     windowAccess: WindowAccessPreview.controller(), screenCapture: ScreenCaptureAccessPreview.controller())
}
#Preview("Multiple displays — dark") {
    let profiles = DisplaySettingsPreview.make()
    DockSettingsView(store: profiles.defaults, profiles: profiles, loginItems: LoginItemPreview.controller(),
                     menuBarIcon: MenuBarIconController(defaults: UserDefaults(suiteName: "SettingsMenuBarPreviewDark") ?? .standard),
                     windowAccess: WindowAccessPreview.controller(), screenCapture: ScreenCaptureAccessPreview.controller()).preferredColorScheme(.dark)
}
#endif
