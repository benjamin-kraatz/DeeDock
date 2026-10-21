import AppKit
import Observation

/// App-wide owner of the one open plugin panel.
///
/// The panel attaches to the plugin's tile on whichever display it was opened from, like the
/// notification feed. Only one dock popover is open at a time, arbitrated by ``DockPopoverPresenter``.
/// The panel is non-activating: hover never opens it, and it becomes key only when clicked, so the
/// plugin's text fields can take typing without DOKK pulling focus from the frontmost app on open.
/// Closing it ends the scene; the plugin's background session keeps running for the tile.
@MainActor
final class DockPluginPanelCoordinator {
    private let plugins: DockPluginController
    private let presenter: DockPopoverPresenter
    private var controller: DockPopoverPanelController<DockPluginPanel>?
    private var state: DockPluginPanelState?
    private weak var source: DockPanelController?
    private var openedAt: Date?
    /// Raised by every open and close, so a size observation from an earlier panel stops itself.
    private var generation = 0
    /// The plugin whose panel is open, by bundle identifier.
    private(set) var openPluginID: String?
    var isOpen: Bool { controller != nil }
    /// Reports a keyboard-opened panel dismissed without returning focus, by display ID.
    var keyboardDismissed: ((String) -> Void)?
    /// Routes the next Settings window to the Plugins page.
    var prepareSettings: (() -> Void)?

    init(plugins: DockPluginController, presenter: DockPopoverPresenter) {
        self.plugins = plugins
        self.presenter = presenter
        presenter.register(.plugin) { [weak self] in self?.close() }
    }

    func isOpen(_ id: String, on panel: DockPanelController? = nil) -> Bool {
        openPluginID == id && controller != nil && (panel == nil || source === panel)
    }

    /// Runs a tile's click: the plugin's panel, or its app when the plugin asks for that.
    func activate(_ id: String, on panel: DockPanelController, keyboard: Bool) {
        if plugins.plugin(id)?.tileState?.primaryAction == .openApp, plugins.plugin(id)?.isStopped == false {
            close()
            plugins.openApp(id)
            return
        }
        toggle(id, on: panel, keyboard: keyboard)
    }

    /// Opens the plugin's panel above its tile on `panel`, or closes it when it is already open there.
    func toggle(_ id: String, on panel: DockPanelController, keyboard: Bool) {
        if isOpen(id, on: panel) { close(returnFocus: keyboard); return }
        close()
        presenter.prepareToOpen(.plugin)
        guard let plugin = plugins.plugin(id), plugin.identity != nil,
              let anchor = panel.popoverAnchor(for: .plugin(id)) else { return }

        let state = DockPluginPanelState()
        state.restart = { [weak self, weak state] in
            state?.restarting = true
            Analytics.performing(.click) { self?.plugins.restart(id, surface: .panel) }
        }
        state.sceneFailed = { [weak self] in self?.plugins.sceneFailed(id) }
        state.menuActions = menuActions(for: id)

        let next = DockPopoverPanelController(anchor: anchor, keyboard: keyboard, clickFocus: true,
                                              ideal: DockPluginPanelGeometry.panelSize(for: plugin.tileState, edge: anchor.edge)) { chrome in
            state.chrome = chrome
        } content: {
            DockPluginPanel(plugin: plugin, state: state)
        }
        generation += 1
        self.state = state
        controller = next
        source = panel
        openPluginID = id
        openedAt = .now
        panel.holdPopover(true)
        presenter.didOpen(.plugin)

        next.canDismissForOutsideClick = { [weak state] in state?.menuTracking != true }
        next.keyHandler = { [weak self] event in
            guard event.keyCode == 53, let self else { return false }
            close(returnFocus: source?.store.keyboardFocus == true)
            return true
        }
        let openGeneration = generation
        next.closed = { [weak self, weak panel] returnFocus in
            guard let self else { return }
            let sourceID = panel?.store.displayID
            if let openedAt {
                Analytics.track(.pluginPanelClosed(duration: Date.now.timeIntervalSince(openedAt),
                                                   stopped: plugins.plugin(id)?.isStopped ?? false))
            }
            plugins.notePanel(id, open: false)
            panel?.holdPopover(false)
            presenter.didClose(.plugin)
            if generation == openGeneration { generation += 1 }
            controller = nil; self.state = nil; source = nil; openPluginID = nil; openedAt = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { keyboardDismissed?(sourceID) }
        }
        next.show()
        plugins.notePanel(id, open: true)
        Analytics.track(.pluginPanelOpened(trigger: Analytics.trigger(keyboard: keyboard), pinnedCount: plugins.pinnedCount))
        followSize(of: plugin, generation: openGeneration)
    }

    /// Follows the dock when it moves, resizes, or scrolls.
    func reanchor() {
        guard controller != nil, let id = openPluginID else { return }
        guard let source, let anchor = source.popoverAnchor(for: .plugin(id)) else { close(); return }
        controller?.update(anchor)
    }

    /// Closes the panel, optionally only when it belongs to `pluginID` or the display `displayID`.
    func close(pluginID: String? = nil, for displayID: String? = nil, returnFocus: Bool = false) {
        guard pluginID == nil || openPluginID == pluginID else { return }
        guard displayID == nil || source?.store.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(); keyboardDismissed = nil; prepareSettings = nil }

    /// Resizes the open panel whenever the plugin asks for a new content size.
    ///
    /// Observation fires once per registration, so each change registers the next one. A newer
    /// panel bumps `generation`, which ends this chain.
    private func followSize(of plugin: DockPlugin, generation expected: Int) {
        withObservationTracking { _ = plugin.tileState?.panelSize } onChange: { [weak self, weak plugin] in
            guard let self, let plugin else { return }
            Task { @MainActor in
                guard self.generation == expected, let source = self.source,
                      let controller = self.controller,
                      let anchor = source.popoverAnchor(for: .plugin(plugin.id)) else { return }
                controller.resize(to: DockPluginPanelGeometry.panelSize(for: plugin.tileState, edge: anchor.edge),
                                  anchor: anchor)
                self.followSize(of: plugin, generation: expected)
            }
        }
    }

    private func menuActions(for id: String) -> DockPluginMenuActions {
        DockPluginMenuActions(
            togglePanel: { [weak self] in self?.close() },
            openApp: { [weak self] in self?.plugins.openApp(id) },
            restart: { [weak self] in
                self?.state?.restarting = true
                self?.plugins.restart(id, surface: .panel)
            },
            chooseItem: { [weak self] in self?.plugins.chooseMenuItem($0, of: id) },
            unpin: { [weak self] in self?.plugins.setPinned(id, false, surface: .panel) },
            // The More button opens the Settings window afterwards; only a view can.
            openSettings: { [weak self] in
                self?.prepareSettings?()
                self?.close()
            })
    }
}
