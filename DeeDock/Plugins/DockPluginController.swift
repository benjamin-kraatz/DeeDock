import AppKit
import ExtensionFoundation
import Observation

/// App-wide owner of DOKK's plugins: discovery, pins, one background session per pinned plugin,
/// and the approval window.
///
/// Every display's dock shows the same pinned plugins, after the apps and before DOKK's own tiles.
/// A plugin runs only while it is pinned: unpinning, turning it off in the system window, or
/// uninstalling it ends its session. Plugins waiting for approval are only counted, for Settings;
/// they never appear in the dock.
///
/// Lifecycle: ``start()`` once from the coordinator, ``stop()`` on teardown. Both run on the main
/// actor, and `stop()` ends every session and observer this owns.
@MainActor @Observable
final class DockPluginController {
    /// Enabled plugins: pinned ones in tile order, then the rest by name.
    private(set) var plugins: [DockPlugin] = []
    /// Installed plugins nobody has turned on yet.
    private(set) var waitingCount = 0
    /// Plugins turned off in the system window.
    private(set) var disabledCount = 0
    /// False until discovery first reports, so Settings never shows "no plugins" prematurely.
    private(set) var hasInventory = false
    /// Pinned, enabled plugins as the docks project them.
    private(set) var dockItems: [PluginDockItem] = []

    /// Called whenever ``dockItems`` changes, so every dock rebuilds its entries.
    @ObservationIgnored var dockItemsChanged: (() -> Void)?
    /// Asks the panel owner to close the panel of the plugin with this ID, if it is open.
    @ObservationIgnored var closePanel: ((String) -> Void)?
    /// Whether the panel of the plugin with this ID is open; read for analytics only.
    @ObservationIgnored var isPanelOpen: ((String) -> Bool)?

    @ObservationIgnored private let discovery = DockPluginDiscovery()
    @ObservationIgnored private let pins: DockPluginPinStore
    @ObservationIgnored private let approval = DockPluginApprovalWindow()
    @ObservationIgnored private var sessions: [String: DockPluginConnection] = [:]
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reportedCounts: [Int]?
    /// Plugins whose panel is open. A session that connects later, after a restart or a slow
    /// launch, is told so once its first state arrives, since `panelOpened` sent earlier was lost.
    @ObservationIgnored private var openPanels: Set<String> = []

    /// - Parameter pins: Where pins are saved. Nil uses the app's defaults.
    init(pins: DockPluginPinStore? = nil) {
        self.pins = pins ?? DockPluginPinStore()
    }

    /// Starts discovery and re-checks for plugins whenever DOKK comes to the front, because
    /// installs made while DOKK runs are not reported on their own.
    func start() {
        guard !started else { return }
        started = true
        discovery.changed = { [weak self] in self?.apply($0) }
        discovery.start()
        approval.closed = { [weak self] in self?.discovery.rescan(force: true) }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discovery.rescan() }
        }
    }

    /// Ends every session (telling each plugin first), the monitor, and the activation observer.
    func stop() {
        guard started else { return }
        started = false
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        discovery.stop()
        approval.closed = nil
        approval.close()
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        openPanels.removeAll()
        for plugin in plugins { plugin.status = .idle }
        dockItemsChanged = nil
        closePanel = nil
        isPanelOpen = nil
    }

    // MARK: - Queries

    func plugin(_ id: String) -> DockPlugin? { plugins.first { $0.id == id } }

    func isPinned(_ id: String) -> Bool { pins.value.isPinned(id) }

    var pinnedCount: Int { dockItems.count }

    // MARK: - Commands

    /// Re-checks for installed plugins now, for example when the Plugins page opens.
    func rescan() {
        discovery.rescan(force: true)
        for session in sessions.values { session.refresh() }
    }

    /// Pins or unpins a plugin's tile. Pinning starts the plugin; unpinning closes its panel and
    /// ends its session.
    func setPinned(_ id: String, _ pinned: Bool, surface: AnalyticsPluginSurface) {
        guard pins.value.isPinned(id) != pinned else { return }
        pins.update { pinned ? $0.pin(id) : $0.unpin(id) }
        Analytics.track(.pluginPinChanged(pinned: pinned, surface: surface))
        if pinned {
            if let plugin = plugin(id) { connect(plugin) }
        } else {
            closePanel?(id)
            disconnect(id)
        }
        reorder()
        publishDockItems()
        reportCounts()
    }

    /// Starts a stopped plugin again. An open panel reloads its scene once the session is back.
    func restart(_ id: String, surface: AnalyticsPluginSurface) {
        guard let plugin = plugin(id), pins.value.isPinned(id), plugin.status == .stopped else { return }
        Analytics.track(.pluginRestarted(surface: surface))
        sessions.removeValue(forKey: id)?.stop()
        plugin.noteRestart()
        connect(plugin)
    }

    /// Opens the app the plugin ships in.
    func openApp(_ id: String) {
        guard let url = plugin(id)?.app.url else { return }
        closePanel?(id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Reports a chosen plugin menu item back to the plugin.
    func chooseMenuItem(_ itemID: String, of id: String) {
        sessions[id]?.send(.menuItemChosen(itemID))
    }

    /// Tells the plugin its panel opened or closed.
    func notePanel(_ id: String, open: Bool) {
        if open { openPanels.insert(id) } else { openPanels.remove(id) }
        sessions[id]?.send(open ? .panelOpened : .panelClosed)
    }

    /// The panel's scene ended with an error: the plugin process is gone or could not show it.
    /// The background session usually reports the same exit; whichever comes first wins. While a
    /// plugin is starting, only its session decides, so a late error from the scene it replaced
    /// cannot stop the restart.
    func sceneFailed(_ id: String) {
        guard let plugin = plugin(id), plugin.status == .running else { return }
        markStopped(plugin)
    }

    /// Shows the system window where people approve plugins.
    func showApprovalWindow() {
        Analytics.track(.pluginsManageOpened(waitingCount: waitingCount))
        approval.show()
    }

    // MARK: - Inventory

    private func apply(_ inventory: DockPluginInventory) {
        hasInventory = true
        waitingCount = inventory.waiting
        disabledCount = inventory.disabled
        let identities = inventory.enabled
        // A plugin seen enabled for the first time gets a tile at the end of the plugin section.
        var newlyPinned: [String] = []
        pins.update { newlyPinned = $0.adopt(identities.map(\.bundleIdentifier)) }
        for _ in newlyPinned { Analytics.track(.pluginPinChanged(pinned: true, surface: .automatic)) }

        let existing = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0) })
        var next: [DockPlugin] = []
        for identity in identities {
            let id = identity.bundleIdentifier
            guard !next.contains(where: { $0.id == id }) else { continue }
            if let plugin = existing[id] {
                // A reinstalled or updated plugin gets a new identity; its old session serves the old binary.
                if plugin.identity?.id != identity.id {
                    plugin.update(identity: identity)
                    if sessions[id] != nil {
                        disconnect(id)
                        plugin.noteRestart()
                    }
                }
                next.append(plugin)
            } else {
                next.append(DockPlugin(id: id, extensionName: identity.localizedName,
                                       app: DockPluginApp.resolve(extension: id, fallbackName: identity.localizedName),
                                       identity: identity))
            }
        }
        let remaining = Set(next.map(\.id))
        for plugin in plugins where !remaining.contains(plugin.id) {
            closePanel?(plugin.id)
            disconnect(plugin.id)
        }
        plugins = next
        for plugin in plugins where pins.value.isPinned(plugin.id) && sessions[plugin.id] == nil
            && plugin.status != .stopped {
            connect(plugin)
        }
        reorder()
        publishDockItems()
        reportCounts()
    }

    /// Pinned plugins in tile order first, then the others by name, as Settings lists them.
    private func reorder() {
        let order = pins.value.pinned
        plugins.sort { lhs, rhs in
            switch (order.firstIndex(of: lhs.id), order.firstIndex(of: rhs.id)) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func publishDockItems() {
        let items = plugins.filter { pins.value.isPinned($0.id) }.map {
            PluginDockItem(pluginID: $0.id, title: $0.title, icon: $0.app.icon, isStopped: $0.isStopped)
        }
        guard items != dockItems else { return }
        dockItems = items
        dockItemsChanged?()
    }

    /// Sends the counts once per distinct value, not on every monitor refresh.
    private func reportCounts() {
        let counts = [plugins.count, waitingCount, disabledCount, dockItems.count]
        guard counts != reportedCounts else { return }
        reportedCounts = counts
        Analytics.track(.pluginsCounted(enabledCount: counts[0], waitingCount: counts[1],
                                        disabledCount: counts[2], pinnedCount: counts[3]))
    }

    // MARK: - Sessions

    private func connect(_ plugin: DockPlugin) {
        guard let identity = plugin.identity, sessions[plugin.id] == nil else { return }
        let id = plugin.id
        plugin.status = .starting
        let session = DockPluginConnection(identity: identity) { [weak self, weak plugin] event in
            guard let self, let plugin else { return }
            switch event {
            case .state(let state):
                let titleChanged = plugin.tileState?.title != state.title
                let wasStopped = plugin.isStopped
                if plugin.receive(state), openPanels.contains(id) { sessions[id]?.send(.panelOpened) }
                if titleChanged || wasStopped { publishDockItems() }
            case .request(let request):
                handle(request, from: id)
            case .ended(let unexpected):
                sessions[id] = nil
                if unexpected { markStopped(plugin) } else { plugin.status = .idle }
            }
        }
        sessions[id] = session
        session.start()
        publishDockItems()
    }

    private func disconnect(_ id: String) {
        sessions.removeValue(forKey: id)?.stop()
        plugin(id)?.status = .idle
    }

    private func markStopped(_ plugin: DockPlugin) {
        guard plugin.status != .stopped else { return }
        sessions.removeValue(forKey: plugin.id)?.stop()
        plugin.status = .stopped
        Analytics.track(.pluginStopped(panelOpen: isPanelOpen?(plugin.id) ?? false))
        publishDockItems()
    }

    private func handle(_ request: DOKKPluginRequest, from id: String) {
        switch request {
        case .closePanel: closePanel?(id)
        case .openApp: openApp(id)
        }
    }
}
