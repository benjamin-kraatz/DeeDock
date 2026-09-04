import SwiftUI

/// The Shelf tile. Clicking opens the staging panel; dragging it carries every staged reference.
struct DockShelfButton: View {
    let item: ShelfDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private
        var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(
            settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction,
            reduceTransparency: reduceTransparency
        ).icons
    }

    var body: some View {
        Button {
            interaction.openShelf?()
        } label: {
            DockIconPresentation(
                icon: item.icon,
                size: size,
                edge: interaction.layout.edge,
                available: true,
                running: false,
                launching: false,
                keyboardSelected: selected,
                artworkOpacity: artworkOpacity,
                artworkAnimation: interaction.idleFade.animation
            )
            .overlay(alignment: .topTrailing) {
                if !item.isEmpty { badge }
            }
            .overlay {
                if interaction.shelfTargeted {
                    DockDocumentHighlight(emphasized: false).allowsHitTesting(
                        false
                    )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            // Click opens; a drag past the threshold hands every staged reference to AppKit.
            DockShelfTileDragSourceView(
                enabled: !item.isEmpty,
                primaryAction: { interaction.openShelf?() },
                begin: { view, event in interaction.beginShelfDrag?(view, event)
                },
                tracking: { interaction.sourceTrackingChanged?($0) }
            )
        }
        .overlay {
            ShelfContextMenuBridge(
                item: item,
                interaction: interaction,
                openSettings: {
                    interaction.prepareSettings?()
                    NSApp.activate()
                    openSettings()
                },
                clearShelf: confirmClear,
                tracking: menuTracking
            )
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in
            accessibilityFocus(focused)
        }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(.shelfName))
        .accessibilityValue(Text(.shelfItemCount(count: item.count)))
        .accessibilityHint(Text(.shelfOpenHint))
        .accessibilityAction(named: Text(.shelfOpen)) {
            interaction.openShelf?()
        }
        .accessibilityAction(named: Text(.shelfClear)) { confirmClear() }
    }

    private var badge: some View {
        Text(item.count, format: .number)
            .font(.system(size: max(9, size * 0.22), weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, max(4, size * 0.11))
            .padding(.vertical, max(1, size * 0.03))
            .background(Color.accentColor, in: .capsule)
            .overlay(
                Capsule().strokeBorder(.background.opacity(0.7), lineWidth: 1)
            )
            .offset(x: size * 0.12, y: -size * 0.08)
            .accessibilityHidden(true)
    }

    private func confirmClear() {
        guard !item.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: .shelfClearConfirmationTitle)
        alert.informativeText = String(
            localized: .shelfClearConfirmationMessage
        )
        let clearButton = alert.addButton(
            withTitle: String(localized: .shelfClearConfirm)
        )
        clearButton.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .shelfClearCancel))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            interaction.clearShelf?()
        }
    }
}

/// Native mouse tracking for the Shelf tile, matching the pin click and drag thresholds.
private struct DockShelfTileDragSourceView: NSViewRepresentable {
    let enabled: Bool
    let primaryAction: () -> Void
    let begin: (NSView, NSEvent) -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.enabled = enabled
        view.primaryAction = primaryAction
        view.begin = begin
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) {
        view.stop()
    }

    final class SourceView: NSView {
        var enabled = false
        var primaryAction: (() -> Void)?
        var begin: ((NSView, NSEvent) -> Void)?
        var tracking: ((Bool) -> Void)?
        private var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                !event.modifierFlags.contains(.control)
            else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            tracking?(true)
            defer { tracking?(false) }
            let origin = event.locationInWindow
            while !stopped,
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                    until: .distantFuture,
                    inMode: .eventTracking,
                    dequeue: true
                )
            {
                if next.type == .keyDown {
                    if next.keyCode == 53 { return }
                    continue
                }
                if next.type == .leftMouseUp {
                    if bounds.contains(
                        convert(next.locationInWindow, from: nil)
                    ) {
                        primaryAction?()
                    }
                    return
                }
                guard enabled else { continue }
                if hypot(
                    next.locationInWindow.x - origin.x,
                    next.locationInWindow.y - origin.y
                ) >= DockDragGeometry.startDistance {
                    begin?(self, next)
                    return
                }
            }
        }
        func stop() {
            stopped = true
            tracking?(false)
            tracking = nil
            primaryAction = nil
            begin = nil
        }
    }
}

private struct ShelfContextMenuBridge: NSViewRepresentable {
    let item: ShelfDockItem
    let interaction: DockInteraction
    let openSettings: () -> Void
    let clearShelf: () -> Void
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.item = item
        view.interaction = interaction
        view.openSettings = openSettings
        view.clearShelf = clearShelf
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) {
        view.stop()
    }

    final class MenuView: NSView, NSMenuDelegate {
        var item: ShelfDockItem?
        weak var interaction: DockInteraction?
        var openSettings: (() -> Void)?
        var clearShelf: (() -> Void)?
        var tracking: ((Bool) -> Void)?
        private var trackedMenu: NSMenu?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                event.type == .rightMouseDown
                    || (event.type == .leftMouseDown
                        && event.modifierFlags.contains(.control))
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
            add(
                .shelfOpen,
                action: #selector(open),
                symbol: "rectangle.stack.fill",
                to: menu
            )
            add(
                .shelfClear,
                action: #selector(clear),
                symbol: "rectangle.stack",
                to: menu,
                enabled: item?.isEmpty == false
            )
            menu.addItem(.separator())
            add(
                .actionSettings,
                action: #selector(settings),
                symbol: "gear",
                to: menu
            )
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        private func add(
            _ title: LocalizedStringResource,
            action: Selector,
            symbol: String,
            to menu: NSMenu,
            enabled: Bool = true
        ) {
            let entry = NSMenuItem(
                title: String(localized: title),
                action: action,
                keyEquivalent: ""
            )
            entry.target = self
            entry.isEnabled = enabled
            entry.image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: nil
            )
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func open() { interaction?.openShelf?() }
        @objc private func clear() { clearShelf?() }
        @objc private func settings() { openSettings?() }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            openSettings = nil
            clearShelf = nil
            item = nil
        }
    }
}

#if DEBUG
    #Preview("Empty and staged") {
        HStack(spacing: 20) {
            DockShelfButton(
                item: ShelfDockItem(
                    count: 0,
                    icon: NSImage(
                        systemSymbolName: "rectangle.stack",
                        accessibilityDescription: nil
                    )!
                ),
                size: 48,
                selected: false,
                interaction: DockInteraction(),
                menuTracking: { _ in },
                accessibilityFocus: { _ in }
            )
            DockShelfButton(
                item: ShelfDockItem(
                    count: 3,
                    icon: NSImage(
                        systemSymbolName: "rectangle.stack.fill",
                        accessibilityDescription: nil
                    )!
                ),
                size: 48,
                selected: false,
                interaction: DockInteraction(),
                menuTracking: { _ in },
                accessibilityFocus: { _ in }
            )
            DockShelfButton(
                item: ShelfDockItem(
                    count: 12,
                    icon: NSImage(
                        systemSymbolName: "rectangle.stack.fill",
                        accessibilityDescription: nil
                    )!
                ),
                size: 48,
                selected: true,
                interaction: DockInteraction(),
                menuTracking: { _ in },
                accessibilityFocus: { _ in }
            )
        }
        .padding(30)
    }
#endif
