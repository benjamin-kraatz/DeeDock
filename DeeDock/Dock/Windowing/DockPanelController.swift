import AppKit

/// Owns one panel, its visibility deadlines, and scoped interaction holds. Global events belong to the coordinator.
@MainActor
final class DockPanelController {
    let store: DockStore
    let visibility: DockVisibilityController
    let interaction = DockInteraction()
    private let panel: DockPanel
    private(set) var geometry: DockPresentationGeometry?
    private var mouseHeld = false
    private var dragHeld = false
    private var lastDisplay: DisplaySnapshot?
    private var lastSettings: DockSettings?
    private var baseLayout = DockGeometry.layout(count: 0, favoriteCount: 0, availableWidth: 800)
    var invalidateDrag: (() -> Void)?
    private var menuHeld = false
    private var accessibilityIDs: Set<String> = []
    private var stopped = false
    var resignedFocus: (() -> Void)?
    var escape: (() -> Void)?

    init(store: DockStore, settings: DockSettings) {
        self.store = store
        visibility = DockVisibilityController(settings: settings.behavior, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: .appName)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsMouseMovedEvents = true; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DockHostingView(rootView: DockView(store: store, interaction: interaction, visibility: visibility))
        interaction.movePin = { [weak store] id, distance in store?.movePin(id, by: distance) }
        interaction.canMovePin = { [weak store] id, distance in store?.canMovePin(id, by: distance) ?? false }
        interaction.copyPin = { [weak store] reference, displayID in store?.copyPin?(reference, displayID) }
        interaction.geometryDidChange = { [weak self] in self?.updatePointer() }
        interaction.menuTrackingChanged = { [weak self] tracking in
            self?.menuHeld = tracking
            if !tracking { self?.mouseHeld = false }
            self?.updatePointer()
        }
        interaction.accessibilityFocusChanged = { [weak self] id, focused in
            if focused { self?.accessibilityIDs.insert(id) } else { self?.accessibilityIDs.remove(id) }
            self?.updatePointer()
        }
        panel.keyboardHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.resignedKey = { [weak self] in self?.resignedFocus?() }
        visibility.refreshInput = { [weak self] in self?.updatePointer() }
        visibility.didChange = { [weak self] in self?.present() }
        store.errorDidChange = { [weak self] in self?.updatePointer() }
    }

    /// Reuses content and scrolling. Geometry/Space refreshes settle stale motion, never force a hidden dock frontmost.
    func update(display: DisplaySnapshot, settings: DockSettings, resetVisibility: Bool = false) {
        guard !stopped else { return }
        if let previous = lastDisplay, previous != display || lastSettings != settings || resetVisibility { invalidateDrag?() }
        lastDisplay = display; lastSettings = settings
        interaction.pinDestinations = store.pinDestinations
        // A mouse-up can occur while asleep or during display reconfiguration; do not retain a stale hold.
        if resetVisibility && NSEvent.pressedMouseButtons == 0 { mouseHeld = false }
        let reference = DockGeometry.referenceFrame(screenFrame: display.frame, visibleFrame: display.visibleFrame, settings: settings)
        baseLayout = DockGeometry.layout(count: store.items.count, favoriteCount: store.items.filter(\.isFavorite).count,
                                         availableWidth: reference.width, settings: settings)
        let slots = DockRenderSlot.slots(items: store.items, proposal: interaction.dragProposal)
        interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: slots.filter(\.isPinned).count,
                                                 availableWidth: reference.width, settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: interaction.layout, settings: settings)
        let updated = DockPresentationGeometry(screen: display.frame, restingFrame: frame, layout: interaction.layout, settings: settings.behavior)
        let changed = geometry?.windowFrame != updated.windowFrame || geometry?.activation.zone != updated.activation.zone
        geometry = updated
        interaction.contentOrigin = updated.contentOrigin; interaction.windowSize = updated.windowFrame.size
        panel.setFrame(updated.windowFrame, display: true)
        visibility.configure(settings.behavior, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                             geometryChanged: changed || resetVisibility)
        updatePointer(); present()
    }

    /// Native events and animation samples share top-left content coordinates after inverse transformation.
    func updatePointer(eventType: NSEvent.EventType? = nil) {
        guard !stopped, let geometry else { return }
        let local = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: local.x - geometry.contentOrigin.x,
                            y: panel.frame.height - local.y - geometry.contentOrigin.y)
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: geometry.contentSize, reduceMotion: visibility.reduceMotion)
        let rects = [interaction.surfaceRect, interaction.errorRect] + Array(interaction.iconRects.values)
        let inside = visibility.exposesContent && panel.frame.contains(NSEvent.mouseLocation) && rects.contains { sample.paintedRect($0).contains(point) }
        panel.ignoresMouseEvents = !inside
        interaction.pointer = inside ? sample.inverse(point) : nil
        if let eventType {
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(eventType), inside { mouseHeld = true }
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(eventType) { mouseHeld = false }
        }
        visibility.update(activation: geometry.activation.zone.contains(NSEvent.mouseLocation),
                          retained: geometry.activation.retention.contains(NSEvent.mouseLocation),
                          held: dragHeld || mouseHeld || menuHeld || !accessibilityIDs.isEmpty || store.keyboardFocus || store.errorMessage != nil)
    }

    private func present() {
        guard !stopped else { return }
        if !visibility.exposesContent {
            panel.ignoresMouseEvents = true; interaction.pointer = nil
            if panel.isVisible { panel.orderOut(nil) }
        } else {
            if !panel.isVisible { panel.orderFrontRegardless() }
            updatePointer()
        }
    }
    /// Installs native destinations on the hosting view without an overlay that swallows button clicks.
    func connectDragging(_ coordinator: DockDragCoordinator) {
        guard let host = panel.contentView as? DockHostingView<DockView> else { return }
        host.registerForDraggedTypes([DockDragCoordinator.pasteboardType, .fileURL])
        let id = store.displayID
        host.dragEntered = { [weak coordinator] info in coordinator?.entered(info, on: id) ?? [] }
        host.dragPerformed = { [weak coordinator] info in coordinator?.perform(info, on: id) ?? false }
        host.dragExited = { [weak coordinator] in coordinator?.exited() }
        host.dragEnded = { [weak coordinator] in coordinator?.externalEnded() }
        interaction.sourceTrackingChanged = { [weak coordinator] in coordinator?.trackSource($0) }
        interaction.beginDrag = { [weak coordinator] item, view, event in coordinator?.begin(item, from: id, view: view, event: event) }
        interaction.scrollChanged = { [weak coordinator] in coordinator?.exited() }
        invalidateDrag = { [weak coordinator] in if coordinator?.committing != true { coordinator?.cancel() } }
    }

    private func contentPoint(_ screenPoint: CGPoint) -> CGPoint {
        let local = panel.convertPoint(fromScreen: screenPoint)
        return CGPoint(x: local.x - interaction.contentOrigin.x,
                       y: panel.frame.height - local.y - interaction.contentOrigin.y)
    }

    /// Resting glass in AppKit screen coordinates, including the current viewport clip.
    var restingDragBounds: CGRect {
        let surface = baseLayout.surfaceFrame(sizes: baseLayout.sizes(pointerX: nil, reduceMotion: true))
            .offsetBy(dx: interaction.scrollOffset, dy: 0)
            .intersection(CGRect(x: 0, y: 0, width: baseLayout.viewportWidth, height: baseLayout.panelHeight))
        return CGRect(x: panel.frame.minX + interaction.contentOrigin.x + surface.minX,
                      y: panel.frame.maxY - interaction.contentOrigin.y - surface.maxY,
                      width: surface.width, height: surface.height)
    }

    func containsDragRegion(_ point: CGPoint) -> Bool {
        guard !stopped, let geometry else { return false }
        return geometry.activation.retention.contains(point) || restingDragBounds.contains(point)
            || (visibility.exposesContent && interaction.containsDockPoint(contentPoint(point)))
    }

    func insertionIndex(at point: CGPoint) -> Int? {
        guard visibility.exposesContent, interaction.containsDockPoint(contentPoint(point)) else { return nil }
        return DockDragGeometry.insertion(point: contentPoint(point), scrollOffset: interaction.scrollOffset,
                                          layout: baseLayout, pinCount: store.pins.count)
    }

    func setDragPresentation(proposal: DockDragProposal?, source: String?, targeted: Bool, message: LocalizedStringResource?) {
        guard !stopped else { return }
        let changed = interaction.dragProposal != proposal
        interaction.dragProposal = proposal
        interaction.dragSourceID = source
        interaction.dragActive = source != nil || targeted
        interaction.dragMessage = message
        // Only revealed destinations are held. Hidden targets must still satisfy the configured dwell.
        dragHeld = source != nil || (targeted && visibility.exposesContent)
        if !interaction.dragActive && NSEvent.pressedMouseButtons == 0 { mouseHeld = false }
        if source != nil { visibility.showImmediately() }
        if changed, let display = lastDisplay, let settings = lastSettings { update(display: display, settings: settings) }
        else { updatePointer() }
    }

    func dragScrollVelocity(at point: CGPoint) -> CGFloat {
        guard visibility.exposesContent, interaction.dragActive, interaction.layout.canvasWidth > interaction.layout.viewportWidth else { return 0 }
        let velocity = DockDragGeometry.scrollVelocity(x: contentPoint(point).x, width: interaction.layout.viewportWidth)
        if velocity < 0 && interaction.scrollOffset >= 0 { return 0 }
        if velocity > 0 && -interaction.scrollOffset >= interaction.layout.canvasWidth - interaction.layout.viewportWidth { return 0 }
        return velocity
    }
    func scrollDuringDrag(at point: CGPoint, elapsed: Double) {
        interaction.scrollRequest += dragScrollVelocity(at: point) * elapsed
    }

    func owns(_ window: NSWindow?) -> Bool { window === panel }
    func focus() {
        store.keyboardFocus = true
        visibility.showImmediately()
        panel.acceptsKeyboardFocus = true
        store.selectedID = store.selectedID ?? store.items.first?.id
        NSApp.activate(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(panel)
        updatePointer()
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard store.keyboardFocus else { return false }
        switch event.keyCode {
        case 123, 124:
            let distance = event.keyCode == 123 ? -1 : 1
            if event.modifierFlags.contains(.option), let id = store.selectedID { store.movePin(id, by: distance) }
            else { store.moveSelection(by: distance) }
        case 36, 76: store.openSelection()
        case 53: escape?()
        default: return false
        }
        return true
    }
    /// The coordinator clears its focus owner before this potentially reentrant resign operation.
    func endFocus() {
        store.keyboardFocus = false; store.selectedID = nil; panel.acceptsKeyboardFocus = false
        panel.resignKey(); updatePointer()
    }
    func stop() {
        invalidateDrag?(); invalidateDrag = nil
        stopped = true; visibility.stop()
        interaction.sourceTrackingChanged = nil
        interaction.beginDrag = nil; interaction.movePin = nil; interaction.canMovePin = nil
        interaction.copyPin = nil; interaction.scrollChanged = nil
        panel.contentView?.unregisterDraggedTypes()
        interaction.geometryDidChange = nil; interaction.menuTrackingChanged = nil; interaction.accessibilityFocusChanged = nil
        panel.resignedKey = nil; panel.keyboardHandler = nil; resignedFocus = nil; escape = nil
        accessibilityIDs.removeAll(); mouseHeld = false; menuHeld = false; dragHeld = false
        store.stop(); panel.close(); panel.contentView = nil
    }
}
