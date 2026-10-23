import SwiftUI

/// A pinned plugin's dock tile.
///
/// Drawn like every other tile: the app's icon and a red badge. A click opens the plugin's panel
/// (or its app, if the plugin asks for that). A stopped plugin turns grey with a restart chip and
/// hides its stale badge; the tile's menu and the panel offer Restart. Hover never opens anything
/// and nothing here takes focus by itself.
///
/// Badge and status are read live from the shared ``DockPlugin``, so a plugin pushing a new badge
/// redraws this tile alone.
struct DockPluginButton: View {
    let item: PluginDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var plugin: DockPlugin? { interaction.plugins?.plugin(item.pluginID) }
    private var stopped: Bool { plugin?.isStopped ?? item.isStopped }
    private var badge: (label: String, style: DockAppBadge.Style)? { plugin?.badge }

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
                              idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openPlugin?(item.pluginID) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: .notRunning, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation,
                                 badgeLabel: badge?.label, badgeStyle: badge?.style ?? .count,
                                 badgeAttention: badge != nil) {
                DockPluginTileArtwork(icon: item.icon, stopped: stopped, size: size)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            if let plugin {
                DockPluginContextMenuBridge(plugin: plugin, interaction: interaction,
                                            actions: actions(for: plugin), tracking: menuTracking)
            }
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(verbatim: plugin?.title ?? item.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text(plugin?.tileState?.primaryAction == .openApp
                                ? .pluginTileOpenAppHint(plugin?.app.name ?? item.title) : .pluginTileOpenPanelHint))
        .accessibilityActions {
            if stopped {
                Button { Analytics.performing(.voiceOver) { interaction.plugins?.restart(item.pluginID, surface: .tile) } }
                    label: { Text(.pluginMenuRestart) }
            }
            if let plugin, plugin.app.url != nil {
                Button { interaction.plugins?.openApp(item.pluginID) } label: { Text(.pluginMenuOpenApp(plugin.app.name)) }
            }
            Button {
                Analytics.performing(.voiceOver) { interaction.plugins?.setPinned(item.pluginID, false, surface: .tile) }
            } label: { Text(.pluginMenuUnpin) }
        }
    }

    /// Stopped first, since it changes what a click does; then the plugin's own words or its badge.
    private var accessibilityValue: Text {
        if stopped { return Text(.pluginStatusStopped) }
        if let value = plugin?.tileState?.accessibilityValue, !value.isEmpty { return Text(verbatim: value) }
        if case .count(let count)? = plugin?.tileState?.badge, count > 0 { return Text(.pluginBadgeCount(count)) }
        if let label = badge?.label, !label.isEmpty { return Text(verbatim: label) }
        return Text(verbatim: "")
    }

    private func actions(for plugin: DockPlugin) -> DockPluginMenuActions {
        let id = plugin.id
        return DockPluginMenuActions(
            togglePanel: { interaction.togglePluginPanel?(id) },
            openApp: { interaction.plugins?.openApp(id) },
            restart: { interaction.plugins?.restart(id, surface: .tile) },
            chooseItem: { interaction.plugins?.chooseMenuItem($0, of: id) },
            unpin: { interaction.plugins?.setPinned(id, false, surface: .tile) },
            openSettings: {
                interaction.preparePluginSettings?()
                openWindow.openDockSettings()
            })
    }
}

/// Right-click actions for a plugin tile.
///
/// An `NSMenu` rather than SwiftUI's `contextMenu`, so the dock panel stays revealed while the
/// menu tracks, the same bridge the notification feed, Trash, and Shelf tiles use.
private struct DockPluginContextMenuBridge: NSViewRepresentable {
    let plugin: DockPlugin
    let interaction: DockInteraction
    let actions: DockPluginMenuActions
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.plugin = plugin
        view.interaction = interaction
        view.actions = actions
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        weak var plugin: DockPlugin?
        weak var interaction: DockInteraction?
        var actions: DockPluginMenuActions?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?
        private let target = DockPluginMenuTarget()

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func rightMouseDown(with event: NSEvent) { show(event) }
        override func mouseDown(with event: NSEvent) { show(event) }

        private func show(_ event: NSEvent) {
            guard let plugin, let actions else { return }
            target.reset()
            target.actions = actions
            let menu = DockPluginMenu.make(for: plugin, panelOpen: interaction?.isPluginPanelOpen?(plugin.id) ?? false,
                                           target: target)
            menu.delegate = self
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            actions = nil
            target.reset()
        }
    }
}
