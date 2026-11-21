import SwiftUI

/// The Flix Files dock tile: the newest item's picture on a glass tile, a red badge for what arrived
/// since you last looked, and the purple "✦ N fit here" pill when phase B1 knows the window in
/// front wants something.
///
/// A click opens the panel above the tile (or closes it). A plain drag carries the newest item;
/// Option-drag moves the tile among the other utilities. Hover never opens anything. The badge and
/// thumbnail come from the shared `FlixTileState`, so a new item redraws this tile alone.
///
/// The badge is drawn by ``FlixTileArtwork`` (the dock's own `DockAppBadge`, in the same corner)
/// rather than by `DockIconPresentation`, so it can pop with each arrival. The pill pops in and
/// out; with Reduce Motion it fades.
struct DockFlixButton: View {
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dockTileHovered) private var hovered
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var tile: FlixTileState? { interaction.flix }
    private var unseen: Int { tile?.unseenCount ?? 0 }

    /// The pill's count while it shows: hidden under the pointer and while the panel is open.
    private var pillCount: Int? {
        guard let count = tile?.fitCount, tile?.isPanelOpen != true, !hovered else { return nil }
        return count
    }

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings, idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        DockIconPresentation(size: size, edge: interaction.layout.edge, available: true,
                             running: tile?.isPanelOpen == true ? .running : .notRunning, launching: false,
                             keyboardSelected: selected, artworkOpacity: artworkOpacity,
                             artworkAnimation: interaction.idleFade.animation) {
            FlixTileArtwork(size: size, thumbnail: tile?.thumbnail, sensitive: tile?.newestIsSensitive == true,
                            arrivals: tile?.arrivals ?? 0,
                            badge: unseen > 0 ? DockNotificationFeedButton.badgeLabel(unseen) : nil,
                            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        }
        .overlay {
            if interaction.flixTargeted {
                DockDocumentHighlight(emphasized: false).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let count = pillCount {
                FlixFitsPill(count: count)
                    .offset(y: -size * 0.62)
                    .allowsHitTesting(false)
                    .transition(FlixMotion.pop(reduceMotion: reduceMotion))
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.dialog, reduceMotion: reduceMotion), value: pillCount)
        .contentShape(.rect)
        .overlay {
            FlixTileSource(hasItem: tile?.newest != nil,
                           click: { interaction.openFlix?() },
                           begin: { view, event in interaction.beginFlixDrag?(view, event) },
                           tracking: { interaction.sourceTrackingChanged?($0) })
        }
        .overlay {
            FlixTileMenuBridge(interaction: interaction, openSettings: {
                interaction.prepareFlixSettings?()
                openWindow.openDockSettings()
            }, tracking: menuTracking)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(.flixName))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text(.flixTileHint))
        .accessibilityAction { interaction.openFlix?() }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .help(Text(tile?.newest.map { .flixTileHelp($0.name) } ?? .flixName))
    }

    private var accessibilityValue: Text {
        var parts: [String] = []
        if unseen > 0 { parts.append(String(localized: .flixUnseenCount(unseen))) }
        if let newest = tile?.newest { parts.append(String(localized: .flixTileNewest(newest.name))) }
        if let fits = tile?.fitCount { parts.append(String(localized: .flixTileFits(fits))) }
        return Text(verbatim: parts.joined(separator: ", "))
    }
}

/// Plain clicks and drags on the tile: click toggles the panel, a drag carries the newest item.
/// Option-presses pass through to the dock's move source, Control-clicks to the menu.
private struct FlixTileSource: NSViewRepresentable {
    let hasItem: Bool
    let click: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var configuration: FlixTileSource?
        private var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window, let configuration else { return }
            configuration.tracking(true)
            defer { configuration.tracking(false) }
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                                       until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { configuration.click() }
                    return
                }
                guard configuration.hasItem else { continue }
                if hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    configuration.begin(self, next)
                    return
                }
            }
        }
        func stop() {
            stopped = true
            configuration?.tracking(false)
            configuration = nil
        }
    }
}

/// Right-click actions for the tile, as an `NSMenu` so the dock stays revealed while it tracks.
private struct FlixTileMenuBridge: NSViewRepresentable {
    let interaction: DockInteraction
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.interaction = interaction
        view.openSettings = openSettings
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        weak var interaction: DockInteraction?
        var openSettings: (() -> Void)?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
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
            let open = NSMenuItem(title: String(localized: .flixTileOpen), action: #selector(openPanel), keyEquivalent: "")
            open.target = self
            open.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)
            menu.addItem(open)
            interaction?.arrangementMenu.addItems(to: menu)
            menu.addItem(.separator())
            let settings = NSMenuItem(title: String(localized: .actionSettings), action: #selector(showSettings), keyEquivalent: "")
            settings.target = self
            settings.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
            menu.addItem(settings)
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func openPanel() { Analytics.performing(.menu) { interaction?.openFlix?() } }
        @objc private func showSettings() { openSettings?() }

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

#if DEBUG
#Preview("Flix tile") {
    let interaction = DockInteraction()
    interaction.flix = FlixTileState(preview: FlixPreviewData.items[0],
                                     thumbnail: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
                                     unseen: 3, fits: 2)
    let sensitive = DockInteraction()
    sensitive.flix = FlixTileState(preview: FlixPreviewData.items[5],
                                   thumbnail: NSImage(systemSymbolName: "person.text.rectangle", accessibilityDescription: nil),
                                   unseen: 12, fits: nil)
    return HStack(spacing: 24) {
        DockFlixButton(size: 50, selected: false, interaction: interaction, menuTracking: { _ in }, accessibilityFocus: { _ in })
        DockFlixButton(size: 50, selected: false, interaction: sensitive, menuTracking: { _ in }, accessibilityFocus: { _ in })
        DockFlixButton(size: 50, selected: true, interaction: DockInteraction(), menuTracking: { _ in },
                       accessibilityFocus: { _ in })
    }
    .padding(60)
}
#endif
