import SwiftUI

/// Opens the shared Session Capsules collection from any display dock.
struct DockCapsulesButton: View {
    let item: CapsuleDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
                              idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openSessionCapsules?() } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: false, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation) {
                CapsuleGlyph(size: size)
            }
                .overlay(alignment: .topTrailing) {
                    if item.count > 0 {
                        Text(item.count, format: .number)
                            .font(.system(size: max(9, size * 0.22), weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white).padding(.horizontal, max(4, size * 0.11))
                            .padding(.vertical, max(1, size * 0.03))
                            .background(Color.accentColor, in: .capsule)
                            .overlay(Capsule().strokeBorder(.background.opacity(0.7), lineWidth: 1))
                            .offset(x: size * 0.12, y: -size * 0.08).accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(.capsulesName))
        .accessibilityValue(Text(.capsulesCount(count: item.count)))
        .accessibilityHint(Text(.capsulesOpenHint))
    }
}

/// A saved capsule remains in the Dock by its generated, user-approved title until deleted.
struct DockSessionCapsuleButton: View {
    let item: SessionCapsuleDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let menuTracking: (Bool) -> Void
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var accessibilityFocused: Bool

    private var artworkOpacity: Double {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
                              idleFraction: interaction.idleFade.fraction,
                              reduceTransparency: reduceTransparency).icons
    }

    var body: some View {
        Button { interaction.openSessionCapsule?(item.capsuleID) } label: {
            DockIconPresentation(size: size, edge: interaction.layout.edge,
                                 available: true, running: false, launching: false,
                                 keyboardSelected: selected, artworkOpacity: artworkOpacity,
                                 artworkAnimation: interaction.idleFade.animation) {
                SessionCapsuleStack(icons: item.applicationIcons, size: size)
            }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            SessionCapsuleContextMenuBridge(capsuleID: item.capsuleID, interaction: interaction,
                                            tracking: menuTracking)
        }
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in accessibilityFocus(focused) }
        .onDisappear { accessibilityFocus(false) }
        .accessibilityLabel(Text(item.title))
        .accessibilityHint(Text(.capsulesSavedOpenHint))
        .accessibilityAction(named: Text(.capsulesResume)) {
            interaction.resumeSessionCapsule?(item.capsuleID)
        }
        .accessibilityAction(named: Text(.capsulesDelete)) {
            interaction.deleteSessionCapsule?(item.capsuleID)
        }
    }
}

/// Right-click actions for a saved capsule tile.
///
/// The menu is an `NSMenu` rather than SwiftUI's `contextMenu` so the Dock panel can keep itself
/// visible while the menu tracks, the same bridge the Trash and Shelf tiles use.
private struct SessionCapsuleContextMenuBridge: NSViewRepresentable {
    let capsuleID: UUID
    let interaction: DockInteraction
    let tracking: (Bool) -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.capsuleID = capsuleID
        view.interaction = interaction
        view.tracking = tracking
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

    final class MenuView: NSView, NSMenuDelegate {
        var capsuleID: UUID?
        weak var interaction: DockInteraction?
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
            add(.capsulesResume, action: #selector(resume), symbol: "play.fill", to: menu)
            menu.addItem(.separator())
            add(.capsulesDelete, action: #selector(delete), symbol: "trash", to: menu)
            trackedMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            tracking?(false)
            trackedMenu = nil
        }

        private func add(_ title: LocalizedStringResource, action: Selector, symbol: String, to menu: NSMenu) {
            let entry = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
            entry.target = self
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking?(true) }
        func menuDidClose(_ menu: NSMenu) { tracking?(false) }
        @objc private func resume() { capsuleID.map { interaction?.resumeSessionCapsule?($0) } }
        @objc private func delete() { capsuleID.map { interaction?.deleteSessionCapsule?($0) } }

        func stop() {
            trackedMenu?.cancelTracking()
            trackedMenu?.delegate = nil
            trackedMenu = nil
            tracking?(false)
            tracking = nil
            interaction = nil
            capsuleID = nil
        }
    }
}
