import AppKit
import SwiftUI

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
    private var pickerHeld = false
    private var lastDisplay: DisplaySnapshot?
    private var lastSettings: DockSettings?
    private var baseLayout = DockGeometry.layout(count: 0, favoriteCount: 0, availableLength: 800)
    var invalidateDrag: (() -> Void)?
    private var menuHeld = false
    private var accessibilityIDs: Set<String> = []
    private var stopped = false
    private var idleSuspended = false
    private var updatingGeometry = false
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
        interaction.idleFade.refreshInput = { [weak self] in self?.updatePointer() }
        visibility.refreshInput = { [weak self] in self?.updatePointer() }
        visibility.didChange = { [weak self] in self?.present() }
        store.presentationDidChange = { [weak self] in
            guard let self, !updatingGeometry, let display = lastDisplay, let settings = lastSettings else { return }
            interaction.tooltips.clear()
            withAnimation(visibility.reduceMotion ? nil : .easeOut(duration: 0.18)) {
                self.update(display: display, settings: settings, animateSectionChange: true)
            }
            interaction.scrollChanged?()
        }
        interaction.toggleSection = { [weak self] in
            guard let self else { return }
            withAnimation(visibility.reduceMotion ? nil : .easeOut(duration: 0.18)) {
                if store.keyboardFocus, let group = store.sections.visibility.collapsedGroup { store.selectedTarget = .group(group) }
                store.sections.toggle()
            }
        }
        store.errorDidChange = { [weak self] in self?.updatePointer() }
    }

    /// Reuses content and scrolling. Geometry/Space refreshes settle stale motion, never force a hidden dock frontmost.
    func update(display: DisplaySnapshot, settings: DockSettings, resetVisibility: Bool = false, animateSectionChange: Bool = false) {
        guard !stopped else { return }
        if let previous = lastDisplay, previous != display || lastSettings != settings || resetVisibility { invalidateDrag?() }
        let edgeChanged = lastSettings?.edge != settings.edge
        let axisChanged = lastSettings?.edge.isVertical != settings.edge.isVertical
        updatingGeometry = true
        defer { updatingGeometry = false; updatePointer(); present() }
        if edgeChanged { interaction.resetGeometry() }
        if axisChanged { interaction.scrollOffset = 0; interaction.scrollRequest = 0 }
        if lastSettings?.tooltipPreset != settings.tooltipPreset || edgeChanged || resetVisibility { interaction.tooltips.clear() }
        lastDisplay = display; lastSettings = settings
        store.sections.configure(settings.appVisibility)
        interaction.tooltipPreset = settings.tooltipPreset
        let exposedIDs = Set(store.entries.compactMap(\.target).map(\.hitID))
        interaction.retainHitRegions(exposedIDs)
        accessibilityIDs.formIntersection(exposedIDs)
        interaction.runningIndicatorStyle = settings.runningIndicatorStyle
        interaction.idleFade.configure(settings,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if resetVisibility { idleSuspended = false }
        if resetVisibility || edgeChanged { interaction.idleFade.reset() }
        interaction.pinDestinations = store.pinDestinations
        // A mouse-up can occur while asleep or during display reconfiguration; do not retain a stale hold.
        if resetVisibility && NSEvent.pressedMouseButtons == 0 { mouseHeld = false }
        let reference = DockGeometry.referenceFrame(screenFrame: display.frame, visibleFrame: display.visibleFrame, settings: settings)
        baseLayout = DockGeometry.layout(count: store.entries.count, favoriteCount: store.entries.filter(\.isPinned).count,
                                         availableLength: settings.edge.length(of: reference.size),
                                         availableDepth: settings.edge.depth(of: reference.size), settings: settings)
        let slots = DockRenderSlot.slots(entries: store.entries, proposal: interaction.dragProposal)
        interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: slots.filter(\.isPinned).count,
                                                 availableLength: settings.edge.length(of: reference.size),
                                         availableDepth: settings.edge.depth(of: reference.size), settings: settings)
        let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: interaction.layout, settings: settings)
        let updated = DockPresentationGeometry(screen: display.frame, restingFrame: frame, layout: interaction.layout, settings: settings.behavior)
        let changed = geometry?.windowFrame != updated.windowFrame || geometry?.activation.zone != updated.activation.zone
        geometry = updated
        interaction.contentOrigin = updated.contentOrigin; interaction.windowSize = updated.windowFrame.size
        if animateSectionChange && !visibility.reduceMotion && visibility.exposesContent {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(updated.windowFrame, display: true)
            }
        } else {
            panel.setFrame(updated.windowFrame, display: true)
        }
        visibility.configure(settings.behavior, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                             geometryChanged: changed || resetVisibility || edgeChanged)
    }

    /// Native events and animation samples share top-left content coordinates after inverse transformation.
    func updatePointer(eventType: NSEvent.EventType? = nil) {
        guard !stopped, !updatingGeometry, let geometry else { return }
        let local = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: local.x - geometry.contentOrigin.x,
                            y: panel.frame.height - local.y - geometry.contentOrigin.y)
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: geometry.contentSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        let rects = [interaction.surfaceRect, interaction.errorRect] + Array(interaction.iconRects.values)
        let inside = visibility.exposesContent && panel.frame.contains(NSEvent.mouseLocation) && rects.contains { sample.paintedRect($0).contains(point) }
        panel.ignoresMouseEvents = !inside
        interaction.pointer = inside ? sample.inverse(point) : nil
        if let eventType {
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(eventType), inside { mouseHeld = true }
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(eventType) { mouseHeld = false }
        }
        let suppress = pickerHeld || idleSuspended || menuHeld || interaction.dragActive || store.errorMessage != nil
            || (visibility.phase != .visible && visibility.phase != .hideDelay)
        if suppress != interaction.suppressTooltips {
            interaction.suppressTooltips = suppress
            if suppress { interaction.tooltips.clear() }
        }
        let held = pickerHeld || dragHeld || mouseHeld || menuHeld || !accessibilityIDs.isEmpty || store.keyboardFocus || store.errorMessage != nil
        // The stable envelope provides a safe pointer route, but rendered content can extend
        // beyond it during layout or magnification. Never hide under a clickable dock region.
        // Tooltips are absent from `rects`, so their transparent reservation stays excluded.
        visibility.update(activation: geometry.activation.zone.contains(NSEvent.mouseLocation),
                          retained: inside || geometry.activation.retention.contains(NSEvent.mouseLocation),
                          held: held)
        // Idle fading retains these hit regions even when their artwork is fully transparent.
        interaction.idleFade.update(interacting: inside || held,
            fullyVisible: !idleSuspended && (visibility.phase == .visible || visibility.phase == .hideDelay))
    }

    private func present() {
        guard !stopped else { return }
        if (visibility.phase == .hiding || !visibility.exposesContent) && !interaction.suppressTooltips {
            interaction.suppressTooltips = true; interaction.tooltips.clear()
        }
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
        host.springTarget = { [weak coordinator] info in coordinator?.springTarget(info, on: id) }
        host.springActivate = { [weak coordinator] info in coordinator?.springActivate(info, on: id) }
        host.springHighlight = { [weak coordinator] info in coordinator?.springHighlight(info, on: id) }
        interaction.sourceTrackingChanged = { [weak coordinator] in coordinator?.trackSource($0) }
        interaction.beginDrag = { [weak coordinator] item, view, event in coordinator?.begin(item, from: id, view: view, event: event) }
        interaction.scrollChanged = { [weak coordinator] in coordinator?.geometryChanged() }
        interaction.geometryDidChange = { [weak self, weak coordinator] in
            self?.updatePointer()
            coordinator?.geometryChanged()
        }
        invalidateDrag = { [weak coordinator] in if coordinator?.committing != true { coordinator?.cancel() } }
    }

    private func contentPoint(_ screenPoint: CGPoint) -> CGPoint {
        let local = panel.convertPoint(fromScreen: screenPoint)
        let point = CGPoint(x: local.x - interaction.contentOrigin.x,
                            y: panel.frame.height - local.y - interaction.contentOrigin.y)
        return DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
            size: interaction.layout.viewportSize, reduceMotion: visibility.reduceMotion,
            edge: interaction.layout.edge).inverse(point)
    }

    /// Resting glass in AppKit screen coordinates, including the current viewport clip.
    var restingDragBounds: CGRect {
        guard let geometry else { return .zero }
        let frame = CGRect(x: panel.frame.minX + geometry.contentOrigin.x,
                           y: panel.frame.maxY - geometry.contentOrigin.y - geometry.contentSize.height,
                           width: geometry.contentSize.width, height: geometry.contentSize.height)
        return DockGeometry.restingGlass(frame: frame, layout: baseLayout, scrollOffset: interaction.scrollOffset)
    }

    func containsDragRegion(_ point: CGPoint) -> Bool {
        guard !stopped, let geometry else { return false }
        return geometry.activation.retention.contains(point) || restingDragBounds.contains(point)
            || (visibility.exposesContent && interaction.containsDockPoint(contentPoint(point)))
    }

    /// Transparent source callout space must not extend the deliberate unpin threshold.
    func protectsDragRemoval(at point: CGPoint, isSource: Bool) -> Bool {
        DockDragGeometry.protectsRemoval(at: point, isSource: isSource, restingGlass: restingDragBounds,
                                         retention: geometry?.activation.retention ?? .zero)
    }

    func insertionIndex(at point: CGPoint) -> Int? {
        let local = contentPoint(point)
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
            size: interaction.layout.viewportSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        guard visibility.exposesContent, panel.frame.contains(point),
              sample.mask.contains(local), interaction.containsDockPoint(local) else { return nil }
        return DockSectionInsertion.index(point: local, scrollOffset: interaction.scrollOffset,
            layout: baseLayout, entries: store.entries, pinCount: store.pins.count, visibility: store.sections.visibility)
    }

    /// Document hits use the same inverse animation transform and viewport-clipped icons as clicks.
    func documentTarget(at point: CGPoint) -> DockItem? {
        guard !stopped, panel.frame.contains(point) else { return nil }
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
            size: interaction.layout.viewportSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        return DockDocumentTarget.app(at: contentPoint(point), entries: store.entries, frames: interaction.iconRects,
                                      mask: sample.mask, exposed: visibility.exposesContent)
    }

    /// Document drags can expose either group; application drags still expose only pins.
    func updateSectionDragHover(at point: CGPoint, valid: Bool, documents: Bool = false) {
        let local = contentPoint(point)
        let group = documents ? store.sections.visibility.collapsedGroup : .pinned
        let control = group.flatMap { interaction.iconRects[DockEntryID.group($0).hitID] }
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
            size: interaction.layout.viewportSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        store.sections.dragHover(valid && visibility.exposesContent && panel.frame.contains(point)
            && sample.mask.contains(local) && control?.contains(local) == true, documents: documents)
    }

    func holdFilePicker(_ held: Bool) {
        pickerHeld = held
        if held { visibility.showImmediately() }
        updatePointer()
    }

    func endSectionDrag() { store.sections.endDrag() }

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
        guard visibility.exposesContent, interaction.dragActive, interaction.layout.canvasLength > interaction.layout.viewportLength else { return 0 }
        let velocity = DockDragGeometry.scrollVelocity(position: interaction.layout.edge.along(contentPoint(point)), length: interaction.layout.viewportLength)
        if velocity < 0 && interaction.scrollOffset >= 0 { return 0 }
        if velocity > 0 && -interaction.scrollOffset >= interaction.layout.canvasLength - interaction.layout.viewportLength { return 0 }
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
        store.selectedTarget = store.selectedTarget ?? store.entries.first?.target
        NSApp.activate(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(panel)
        updatePointer()
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard store.keyboardFocus else { return false }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "o" {
            if let item = store.entries.compactMap(\.item).first(where: { $0.id == store.selectedID }), item.isAvailable {
                interaction.openFiles?(item)
            }
            return true
        }
        if let distance = interaction.layout.edge.navigationStep(keyCode: event.keyCode) {
            if event.modifierFlags.contains(.option), let id = store.selectedID { store.movePin(id, by: distance) }
            else { store.moveSelection(by: distance) }
            return true
        }
        switch event.keyCode {
        case 36, 76: store.openSelection()
        case 49: if case .group = store.selectedTarget { store.openSelection() }
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
    /// Sleep cancels the idle deadline; the next display refresh resumes normal input handling.
    func suspendIdleFading() {
        idleSuspended = true
        interaction.suppressTooltips = true; interaction.tooltips.clear()
        interaction.idleFade.reset()
    }

    func stop() {
        invalidateDrag?(); invalidateDrag = nil
        stopped = true; interaction.suppressTooltips = true; interaction.tooltips.clear(); interaction.toggleSection = nil; interaction.idleFade.stop(); visibility.stop()
        interaction.sourceTrackingChanged = nil
        interaction.prepareSettings = nil; interaction.openFiles = nil
        interaction.beginDrag = nil; interaction.movePin = nil; interaction.canMovePin = nil
        interaction.copyPin = nil; interaction.scrollChanged = nil
        panel.contentView?.unregisterDraggedTypes()
        interaction.geometryDidChange = nil; interaction.menuTrackingChanged = nil; interaction.accessibilityFocusChanged = nil
        panel.resignedKey = nil; panel.keyboardHandler = nil; resignedFocus = nil; escape = nil
        accessibilityIDs.removeAll(); mouseHeld = false; menuHeld = false; dragHeld = false
        store.stop(); panel.close(); panel.contentView = nil
    }
}
