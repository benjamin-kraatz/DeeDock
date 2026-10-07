import SwiftUI

/// The notification feed tile. Clicking opens the feed; the red badge counts what arrived since
/// it was last opened. A Line icon dock draws a red ring instead, which clears as the feed opens.
///
/// The count comes straight from the shared store, so an arriving notification redraws this tile
/// alone. Hover never opens the feed and nothing here takes focus by itself.
struct DockNotificationFeedButton: View {
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool
    /// Counts arrivals, so each one rings the bell once.
    @State private var ring = 0

    private var unreadCount: Int { interaction.notificationFeed?.store.unreadCount ?? 0 }
    private var entryCount: Int { interaction.notificationFeed?.store.entries.count ?? 0 }

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
                              idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openNotificationFeed?() } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: false, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation,
                                 badgeLabel: unreadCount > 0 ? Self.badgeLabel(unreadCount) : nil,
                                 badgeStyle: .count, badgeAttention: unreadCount > 0,
                                 lineIcon: interaction.lineIcon(for: .notificationFeed)) {
                NotificationFeedGlyph(size: size, ring: ring, reduceMotion: reduceMotion)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onChange(of: unreadCount) { previous, current in
            if current > previous { ring += 1 }
        }
        .overlay {
            NotificationFeedContextMenuBridge(
                hasEntries: entryCount > 0,
                interaction: interaction,
                openSettings: {
                    interaction.prepareNotificationFeedSettings?()
                    openWindow.openDockSettings()
                },
                tracking: menuTracking)
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(.notificationFeedName))
        .accessibilityValue(unreadCount > 0 ? Text(.notificationFeedUnread(unreadCount)) : Text(.notificationFeedNoUnread))
        .accessibilityHint(Text(.notificationFeedOpenHint))
        .accessibilityAction(named: Text(.notificationFeedClear)) {
            Analytics.performing(.voiceOver) { interaction.clearNotificationFeed?() }
        }
    }

    /// The badge stays legible on small tiles; VoiceOver still reads the exact count.
    static func badgeLabel(_ count: Int) -> String {
        count > 99 ? "99+" : count.formatted()
    }
}

/// Right-click actions for the notification feed tile.
///
/// An `NSMenu` rather than SwiftUI's `contextMenu`, so the dock panel stays revealed while the
/// menu tracks, the same bridge the Trash and Shelf tiles use.
private struct NotificationFeedContextMenuBridge: NSViewRepresentable {
    let hasEntries: Bool
    let interaction: DockInteraction
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.hasEntries = hasEntries
        view.interaction = interaction
        view.openSettings = openSettings
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        var hasEntries = false
        weak var interaction: DockInteraction?
        var openSettings: (() -> Void)?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?

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
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            add(.notificationFeedOpen, action: #selector(open), symbol: "bell", to: menu)
            add(.notificationFeedClear, action: #selector(clear), symbol: "xmark.circle", to: menu,
                enabled: hasEntries)
            menu.addItem(.separator())
            add(.actionSettings, action: #selector(settings), symbol: "gear", to: menu)
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        private func add(_ title: LocalizedStringResource, action: Selector, symbol: String,
                         to menu: NSMenu, enabled: Bool = true) {
            let entry = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func open() { Analytics.performing(.menu) { interaction?.openNotificationFeed?() } }
        @objc private func clear() { Analytics.performing(.menu) { interaction?.clearNotificationFeed?() } }
        @objc private func settings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            openSettings = nil
        }
    }
}
