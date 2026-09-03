import AppKit

/// Owns one native panel and its local geometry/keyboard handlers. The coordinator owns global events.
@MainActor
final class DockPanelController {
    let store: DockStore
    private let interaction = DockInteraction()
    private let panel: DockPanel
    var resignedFocus: (() -> Void)?
    var escape: (() -> Void)?

    init(store: DockStore) {
        self.store = store
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: .appName)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DockHostingView(rootView: DockView(store: store, interaction: interaction))
        interaction.geometryDidChange = { [weak self] in self?.updatePointer() }
        panel.keyboardHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.resignedKey = { [weak self] in self?.resignedFocus?() }
    }

    /// Reuses the panel and SwiftUI state across arrangement, settings, and application changes.
    func update(display: DisplaySnapshot, settings: DockSettings) {
        let reference = DockGeometry.referenceFrame(screenFrame: display.frame, visibleFrame: display.visibleFrame, settings: settings)
        interaction.layout = DockGeometry.layout(count: store.items.count, favoriteCount: store.items.filter(\.isFavorite).count,
                                                  availableWidth: reference.width, settings: settings)
        panel.setFrame(DockGeometry.panelFrame(referenceFrame: reference, layout: interaction.layout, settings: settings), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        updatePointer()
    }

    func updatePointer() {
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        // AppKit screen points are bottom-left-origin; SwiftUI reports top-left panel coordinates.
        let flipped = CGPoint(x: point.x, y: panel.frame.height - point.y)
        let inside = interaction.containsDockPoint(flipped)
        panel.ignoresMouseEvents = !inside && !interaction.errorRect.contains(flipped)
        let pointer = inside ? flipped : nil
        if interaction.pointer != pointer { interaction.pointer = pointer }
    }

    func owns(_ window: NSWindow?) -> Bool { window === panel }

    func focus() {
        panel.acceptsKeyboardFocus = true
        store.keyboardFocus = true
        store.selectedID = store.selectedID ?? store.items.first?.id
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard store.keyboardFocus else { return false }
        switch event.keyCode {
        case 123: store.moveSelection(by: -1)
        case 124: store.moveSelection(by: 1)
        case 36, 76: store.openSelection()
        case 53: escape?()
        default: return false
        }
        return true
    }

    /// The coordinator clears its focus owner before this potentially reentrant resign operation.
    func endFocus() {
        store.keyboardFocus = false
        store.selectedID = nil
        panel.acceptsKeyboardFocus = false
        panel.resignKey()
    }

    func stop() {
        interaction.geometryDidChange = nil
        panel.resignedKey = nil
        panel.keyboardHandler = nil
        resignedFocus = nil
        escape = nil
        store.stop()
        panel.close()
        panel.contentView = nil
    }
}
