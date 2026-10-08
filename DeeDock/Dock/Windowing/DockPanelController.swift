import AppKit
import SwiftUI

/// Owns one panel, its visibility deadlines, and scoped interaction holds. Global events belong to the coordinator.
@MainActor
final class DockPanelController {
    let store: DockStore
    let visibility: DockVisibilityController
    let interaction = DockInteraction()
    private let panel: DockPanel
    /// Edge glow shown while the pointer nears this dock's activation zone and the dock is hidden.
    private let approach = DockApproachIndicatorController()
    let launcher: LauncherState
    private let launcherPresentation: LauncherPresentationController
    /// The open compact Launcher, if any. Each opening builds a new single-use controller.
    private var compactLauncher: CompactLauncherController?
    var launcherWillOpen: (() -> NSRunningApplication?)?
    private(set) var geometry: DockPresentationGeometry?
    private var mouseHeld = false
    /// When the pointer or a held interaction last touched this dock. Starts at creation so a
    /// relaunch after an update does not count as idle straight away.
    private var lastUse = Date()
    /// Feeds the update idle gate. Wall-clock time, so sleep counts as not using the dock.
    var secondsSinceUse: TimeInterval { max(0, Date().timeIntervalSince(lastUse)) }
    private var dragHeld = false
    private var pickerHeld = false
    private var popoverHeld = false
    private var windowPeekHeld = false
    private var volumeCardHeld = false
    private var modePickerHeld = false
    private var lastDisplay: DisplaySnapshot?
    private var lastSettings: DockSettings?
    private var baseLayout = DockGeometry.layout(count: 0, favoriteCount: 0, availableLength: 800)
    /// Resting content frame before a transient insertion gap changes the panel's dimensions.
    private var baseRestingFrame = CGRect.zero
    var invalidateDrag: (() -> Void)?
    private var menuHeld = false
    private var accessibilityIDs: Set<String> = []
    private var stopped = false
    private var idleSuspended = false
    private var updatingGeometry = false
    var resignedFocus: (() -> Void)?
    var escape: (() -> Void)?
    var exclusiveInteractionBegan: (() -> Void)?
    var windowSearchRequested: (() -> Void)?
    var modePickerRequested: (() -> Void)?
    var timelineRequested: (() -> Void)?
    var isMenuTracking: Bool { menuHeld }

    init(store: DockStore, settings: DockSettings) {
        self.store = store
        launcher = LauncherState(catalog: store.launcherCatalog)
        launcher.dockStore = store
        visibility = DockVisibilityController(settings: settings.behavior, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        launcherPresentation = LauncherPresentationController(panel: panel, state: launcher)
        panel.title = String(localized: .appName)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsMouseMovedEvents = true; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DockHostingView(rootView: DockView(launcher: launcher, store: store, interaction: interaction, visibility: visibility))
        launcherPresentation.didClose = { [weak self] in self?.launcherDidClose() }
        store.openLauncher = { [weak self] in self?.openLauncher() }
        interaction.applicationCatalog = store.launcherCatalog
        interaction.openLauncher = store.openLauncher
        interaction.canMoveUtility = { [weak store] id, distance in store?.canMoveUtility(id, by: distance) == true }
        interaction.moveUtility = { [weak store] id, distance in store?.moveUtility(id, by: distance) }
        interaction.canMoveVolume = { [weak store] id, distance in store?.canMoveVolume(id, by: distance) == true }
        interaction.moveVolume = { [weak store] id, distance in store?.moveVolume(id, by: distance) }
        interaction.movePin = { [weak store] id, distance in store?.movePin(id, by: distance) }
        interaction.canMovePin = { [weak store] id, distance in store?.canMovePin(id, by: distance) ?? false }
        interaction.copyPin = { [weak store] reference, displayID in store?.copyPin?(reference, displayID) }
        interaction.removePin = { [weak store] id in _ = store?.removePin(id) }
        interaction.setFolderPresentation = { [weak store] id, value in _ = store?.setFolderPresentation(value, for: id) }
        interaction.openTrash = { [weak store] in store?.openTrash() }
        interaction.emptyTrash = { [weak store] in store?.emptyTrash() }
        interaction.geometryDidChange = { [weak self] in self?.updatePointer() }
        interaction.menuTrackingChanged = { [weak self] tracking in
            if tracking { self?.exclusiveInteractionBegan?() }
            self?.menuHeld = tracking
            if !tracking { self?.mouseHeld = false }
            self?.updatePointer()
        }
        interaction.accessibilityFocusChanged = { [weak self] id, focused in
            if focused { self?.accessibilityIDs.insert(id) } else { self?.accessibilityIDs.remove(id) }
            self?.updatePointer()
        }
        panel.keyboardHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.resignedKey = { [weak self] in
            guard let self else { return }
            // The compact Launcher is its own key window, so the dock resigning key is expected there.
            if launcher.isPresented { if compactLauncher == nil { launcherPresentation.noteWindowResignedKey() } }
            else { resignedFocus?() }
        }
        interaction.idleFade.refreshInput = { [weak self] in self?.updatePointer() }
        visibility.refreshInput = { [weak self] in self?.updatePointer() }
        visibility.didChange = { [weak self] in self?.present() }
        visibility.didReveal = { [weak self] in
            guard let self else { return }
            Analytics.count(.autoHideReveal(zone: visibility.settings.activationLocation, edge: interaction.layout.edge))
        }
        store.presentationDidChange = { [weak self] in
            guard let self, !updatingGeometry, let display = lastDisplay, let settings = lastSettings else { return }
            if QuarantineStampController.shared.armed, launcher.isPresented { closeLauncher() }
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
        if launcher.isPresented, resetVisibility || lastDisplay != display || lastSettings != settings {
            closeActiveLauncher(animated: false, restoreFocus: false)
        }
        let edgeChanged = lastSettings?.edge != settings.edge
        let axisChanged = lastSettings?.edge.isVertical != settings.edge.isVertical
        updatingGeometry = true
        defer { updatingGeometry = false; updatePointer(); present() }
        if edgeChanged { interaction.resetGeometry() }
        if axisChanged { interaction.scrollOffset = 0; interaction.scrollRequest = 0 }
        if lastSettings?.tooltipPreset != settings.tooltipPreset || edgeChanged || resetVisibility { interaction.tooltips.clear() }
        lastDisplay = display; lastSettings = settings
        store.sections.configure(settings.appVisibility)
        store.configureShelf(settings.showShelf)
        store.configureNotificationFeed(settings.showNotificationFeed)
        store.configureLauncherPosition(settings.launcherPosition)
        store.configureSessionCapsules(settings.showSessionCapsules)
        store.configureTrash(settings.showTrash)
        store.configureVolumes(VolumeVisibility(settings: settings))
        interaction.confirmsTrashEmpty = settings.confirmBeforeEmptyingTrash
        interaction.tooltipPreset = settings.tooltipPreset
        let exposedIDs = Set(store.entries.compactMap(\.target).map(\.hitID))
        interaction.retainHitRegions(exposedIDs)
        accessibilityIDs.formIntersection(exposedIDs)
        interaction.runningIndicatorStyle = settings.runningIndicatorStyle
        interaction.iconStyle = settings.iconStyle
        interaction.lineIconMotion = settings.lineIconMotion
        launcher.usesLineIcons = settings.iconStyle == .line && settings.launcherLineIcons
        launcher.lineIconMotion = settings.lineIconMotion
        interaction.animateIndicators = settings.animateIndicators
        interaction.launchAnimation = settings.launchAnimation
        interaction.showAppBadgeCounts = settings.showAppBadgeCounts
        interaction.soapBubbles.isEnabled = settings.soapBubbleEffects
        if !settings.soapBubbleEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            interaction.soapBubbles.removeAll()
        }
        interaction.idleFade.configure(settings,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if resetVisibility { idleSuspended = false }
        if resetVisibility || edgeChanged { interaction.idleFade.reset() }
        interaction.pinDestinations = store.pinDestinations
        // A mouse-up can occur while asleep or during display reconfiguration; do not retain a stale hold.
        if resetVisibility && NSEvent.pressedMouseButtons == 0 { mouseHeld = false }
        let reference = DockGeometry.referenceFrame(screenFrame: display.frame, visibleFrame: display.visibleFrame, settings: settings)
        let timelineCallout: CGFloat? = interaction.timeline?.isActive(on: store.displayID) == true
            ? (settings.edge.isVertical ? 260 : 168)
            : nil
        let restingSections = DockLauncherPlacement.sectionCounts(store.entries)
        baseLayout = DockGeometry.layout(count: store.entries.count, favoriteCount: restingSections.favorites,
                                         utilityCount: restingSections.utilities,
                                         leadingUtilityCount: restingSections.leading,
                                         availableLength: settings.edge.length(of: reference.size),
                                         availableDepth: settings.edge.depth(of: reference.size), settings: settings,
                                         calloutReserve: timelineCallout)
        baseRestingFrame = DockGeometry.panelFrame(referenceFrame: reference, layout: baseLayout, settings: settings)
        let slots = DockRenderSlot.slots(entries: store.entries, proposal: interaction.dragProposal)
        let sections = DockLauncherPlacement.sectionCounts(slots)
        interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: sections.favorites,
                                                 utilityCount: sections.utilities,
                                                 leadingUtilityCount: sections.leading,
                                                 availableLength: settings.edge.length(of: reference.size),
                                         availableDepth: settings.edge.depth(of: reference.size), settings: settings,
                                         calloutReserve: timelineCallout)
        let frame = DockGeometry.panelFrame(referenceFrame: reference, layout: interaction.layout, settings: settings)
        let updated = DockPresentationGeometry(screen: display.frame, restingFrame: frame, layout: interaction.layout, settings: settings.behavior)
        let changed = geometry?.windowFrame != updated.windowFrame || geometry?.activation.zone != updated.activation.zone
        geometry = updated
        interaction.contentOrigin = updated.contentOrigin; interaction.windowSize = updated.windowFrame.size
        launcherPresentation.origin = restingDragBounds
        if launcher.isPresented {
            // Catalog changes may resize the resting dock, but must not collapse the launcher.
            // The compact Launcher follows its tile instead.
            if let compactLauncher, let anchor = restingLauncherAnchor() { compactLauncher.update(anchor) }
        } else if animateSectionChange && !visibility.reduceMotion && visibility.exposesContent {
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
        let approachEnabled = settings.behavior.autoHide && settings.behavior.approachIndicator
        approach.configure(enabled: approachEnabled,
                           settings: settings.behavior, screenFrame: display.frame, zone: updated.activation.zone,
                           edge: settings.edge, runtimeID: display.runtimeID,
                           ghost: approachEnabled && settings.behavior.approachGhost
                               ? DockApproachGhost.resting(slots: slots, layout: interaction.layout, restingFrame: frame,
                                                           scrollOffset: interaction.scrollOffset,
                                                           showsGlass: settings.showBackground,
                                                           cornerRadius: CGFloat(settings.cornerRadius))
                               : nil,
                           reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                           reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Native events and animation samples share top-left content coordinates after inverse transformation.
    func updatePointer(eventType: NSEvent.EventType? = nil) {
        guard !stopped, !updatingGeometry, let geometry else { return }
        if launcher.isPresented {
            panel.ignoresMouseEvents = false
            interaction.setPointer(nil)
            approach.hide()
            return
        }
        let local = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: local.x - geometry.contentOrigin.x,
                            y: panel.frame.height - local.y - geometry.contentOrigin.y)
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
                                                  size: geometry.contentSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        let rects = [interaction.surfaceRect, interaction.errorRect] + Array(interaction.iconRects.values)
        let inside = visibility.exposesContent && panel.frame.contains(NSEvent.mouseLocation) && rects.contains { sample.paintedRect($0).contains(point) }
        let timelineHeld = interaction.timeline?.isActive(on: store.displayID) == true
        panel.ignoresMouseEvents = !inside
        // An open stack makes every dock dismissal-only. Clearing the pointer settles
        // magnification and hover without changing the dock's visible hold region.
        // Timeline scrub keeps the resting axis stable, so magnification is suppressed.
        interaction.setPointer(inside && !popoverHeld && !modePickerHeld && !timelineHeld ? sample.inverse(point) : nil)
        // Scrub only on the glass, and only from real pointer events. The glance card is a
        // rest area: mapping its X/Y onto the axis jumped the playhead and cancelled pin dwell.
        // Geometry-only refresh (apply preview, catalog) must not rematerialize the playhead.
        let onGlanceCard = !interaction.errorRect.isEmpty && sample.paintedRect(interaction.errorRect).contains(point)
        if timelineHeld, eventType != nil, (inside || mouseHeld), !onGlanceCard {
            let dockPoint = sample.inverse(point)
            let edge = interaction.layout.edge
            let rect = interaction.surfaceRect
            interaction.timeline?.update(along: edge.along(dockPoint) - edge.along(rect.origin),
                                         length: max(edge.length(of: rect.size), 1))
        }
        if let eventType {
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(eventType), inside { mouseHeld = true }
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(eventType) { mouseHeld = false }
        }
        let suppress = pickerHeld || popoverHeld || windowPeekHeld || volumeCardHeld || modePickerHeld || idleSuspended || menuHeld || interaction.dragActive || store.errorMessage != nil
            || timelineHeld
            || (visibility.phase != .visible && visibility.phase != .hideDelay)
        if suppress != interaction.suppressTooltips {
            interaction.suppressTooltips = suppress
            if suppress { interaction.tooltips.clear() }
        }
        let held = pickerHeld || popoverHeld || windowPeekHeld || volumeCardHeld || modePickerHeld || dragHeld || mouseHeld || menuHeld || !accessibilityIDs.isEmpty || store.keyboardFocus || store.errorMessage != nil || timelineHeld
        if inside || held { lastUse = Date() }
        // The stable envelope provides a safe pointer route, but rendered content can extend
        // beyond it during layout or magnification. Never hide under a clickable dock region.
        // Tooltips are absent from `rects`, so their transparent reservation stays excluded.
        let activationHovered = geometry.activation.zone.contains(NSEvent.mouseLocation)
        visibility.update(activation: activationHovered,
                          retained: inside || geometry.activation.retention.contains(NSEvent.mouseLocation),
                          held: held)
        // Only a dock that is still hidden invites the approach glow; any reveal fades it out.
        approach.update(pointer: NSEvent.mouseLocation,
                        armed: visibility.phase == .hidden || visibility.phase == .revealDelay)
        // The activation zone also restores idle opacity, including when auto-hide is off.
        // Keep fading suspended while hovered, even when the artwork is fully transparent.
        interaction.idleFade.update(interacting: inside || activationHovered || held,
            fullyVisible: !idleSuspended && (visibility.phase == .visible || visibility.phase == .hideDelay))
    }

    private func present() {
        guard !stopped, !launcher.isPresented else { return }
        if (visibility.phase == .hiding || !visibility.exposesContent) && !interaction.suppressTooltips {
            interaction.suppressTooltips = true; interaction.tooltips.clear()
        }
        interaction.exposesContent = visibility.exposesContent
        if !visibility.exposesContent {
            panel.ignoresMouseEvents = true; interaction.setPointer(nil)
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
        interaction.beginUtilityDrag = { [weak self, weak coordinator] slot, view, event in
            guard self?.interaction.timeline?.isActive != true else { return }
            coordinator?.beginUtility(slot, from: id, view: view, event: event)
        }
        interaction.beginDrag = { [weak self, weak coordinator] item, view, event in
            guard self?.interaction.timeline?.isActive != true else { return }
            coordinator?.begin(item, from: id, view: view, event: event)
        }
        interaction.beginFolderDrag = { [weak self, weak coordinator] item, view, event in
            guard self?.interaction.timeline?.isActive != true else { return }
            coordinator?.begin(item, from: id, view: view, event: event)
        }
        interaction.beginVolumeDrag = { [weak self, weak coordinator] item, view, event in
            guard self?.interaction.timeline?.isActive != true else { return }
            coordinator?.beginVolume(item, from: id, view: view, event: event)
        }
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
        DockGeometry.restingGlass(frame: baseRestingFrame, layout: baseLayout, scrollOffset: interaction.scrollOffset)
    }

    /// Resting pin and folder-stack artwork in AppKit screen space, for peer magnetism.
    ///
    /// Uses the pre-preview layout so an insertion gap cannot make peers chase the drag.
    /// Running-only apps are omitted; the dragged pin is omitted when `pinID` matches.
    func magneticPeerFrames(excluding pinID: String?) -> [CGRect] {
        guard !stopped, visibility.exposesContent, !baseRestingFrame.isEmpty else { return [] }
        let size = baseLayout.iconSize
        return zip(store.entries.indices, store.entries).compactMap { index, entry in
            guard index < baseLayout.restingCenters.count else { return nil }
            let isPeer: Bool
            if let pin = entry.pin {
                isPeer = pin.id != pinID
            } else if case .folder = entry {
                isPeer = true
            } else {
                isPeer = false
            }
            guard isPeer else { return nil }
            let along = baseLayout.restingCenters[index] - interaction.scrollOffset
            let local = baseLayout.buttonFrame(centerAlong: along, size: size)
            return DockEdge.screenRect(local, in: baseRestingFrame)
        }
    }

    func containsDragRegion(_ point: CGPoint) -> Bool {
        if containsLauncherFileDrop(point) { return true }
        guard !stopped, !launcher.isPresented, let geometry else { return false }
        return geometry.activation.retention.contains(point) || restingDragBounds.contains(point)
            || (visibility.exposesContent && interaction.containsDockPoint(contentPoint(point)))
    }

    /// Drops land on the glass, not the transparent presentation margin.
    func containsLauncherFileDrop(_ point: CGPoint) -> Bool {
        guard !stopped, launcher.isPresented, launcher.contentVisible else { return false }
        let window = panel.frame
        guard window.contains(point) else { return false }
        let local = CGPoint(x: point.x - window.minX, y: window.maxY - point.y)
        return launcher.contentRect.contains(local)
    }

    func launcherTarget(at point: CGPoint) -> Bool { utilityTarget(.launcher, at: point) }

    /// Transparent source callout space must not extend the deliberate unpin threshold.
    func protectsDragRemoval(at point: CGPoint, isSource: Bool) -> Bool {
        DockDragGeometry.protectsRemoval(at: point, isSource: isSource, restingGlass: restingDragBounds,
                                         retention: geometry?.activation.retention ?? .zero)
    }

    func insertionIndex(at point: CGPoint) -> Int? {
        // The preview can resize and recenter the native panel. Resolving the next boundary
        // against that transient frame makes the preview invalidate its own hit test and cycle.
        // Keep the whole drag session in the pre-preview content coordinate space instead.
        guard !launcher.isPresented, visibility.exposesContent, restingDragBounds.contains(point), !baseRestingFrame.isEmpty else { return nil }
        let local = CGPoint(x: point.x - baseRestingFrame.minX, y: baseRestingFrame.maxY - point.y)
        return DockSectionInsertion.index(point: local, scrollOffset: interaction.scrollOffset,
            layout: baseLayout, entries: store.entries, pinCount: store.pins.count, visibility: store.sections.visibility)
    }

    /// Utility boundaries use the original layout, so a moving gap cannot retarget itself.
    func utilityInsertionIndex(at point: CGPoint, sourceID: String) -> Int? {
        if sourceID == DockEntryID.launcher.hitID { return launcherInsertionStop(at: point) }
        return insertionIndex(at: point, sourceID: sourceID) { $0.movableUtilityID != nil }
    }

    /// The launcher stop under `point`, an index into ``DockLauncherPlacement/stops(in:)`` for the
    /// entries without the launcher. Like utilities, this reads the resting layout.
    ///
    /// Before the first pin is `start`. Over the pins it is the last pin whose center the pointer
    /// passed. Past the pins, the first trailing tile's leading edge separates "after the last pin"
    /// from `end`, so dropping beside running apps or utilities sends the launcher to the far end.
    func launcherInsertionStop(at point: CGPoint) -> Int? {
        guard !stopped, !launcher.isPresented, visibility.exposesContent,
              restingDragBounds.contains(point) else { return nil }
        let entries = store.entries
        let centers = baseLayout.restingCenters
        guard entries.count <= centers.count, entries.contains(where: \.isLauncher) else { return nil }
        let local = CGPoint(x: point.x - baseRestingFrame.minX, y: baseRestingFrame.maxY - point.y)
        let along = baseLayout.edge.along(local) - interaction.scrollOffset
        let pins = entries.indices.filter { entries[$0].pin != nil }
        let passed = pins.filter { along > centers[$0] }.count
        guard passed == pins.count else { return passed }
        let trailing = entries.indices.first { $0 > (pins.last ?? -1) && !entries[$0].isLauncher }
        guard let trailing else { return pins.count }
        return along > centers[trailing] - baseLayout.iconSize / 2 ? pins.count + 1 : pins.count
    }

    /// Where a dragged drive would land among this dock's drives, or nil when the pointer is
    /// outside their run. Uses the original layout, like utilities.
    func volumeInsertionIndex(at point: CGPoint, sourceID: String) -> Int? {
        insertionIndex(at: point, sourceID: sourceID) { $0.volume != nil }
    }

    /// The gap index among the entries matching `member` (with the source removed), when the
    /// pointer lies within half an icon of the first and last such entry.
    private func insertionIndex(at point: CGPoint, sourceID: String, member: (DockRenderSlot) -> Bool) -> Int? {
        guard !stopped, !launcher.isPresented, visibility.exposesContent,
              restingDragBounds.contains(point) else { return nil }
        let positions = store.entries.indices.filter { member(store.entries[$0]) }
        let centers = baseLayout.restingCenters
        guard let first = positions.first, let last = positions.last, last < centers.count,
              positions.contains(where: { store.entries[$0].id == sourceID }) else { return nil }
        let local = CGPoint(x: point.x - baseRestingFrame.minX, y: baseRestingFrame.maxY - point.y)
        let along = baseLayout.edge.along(local) - interaction.scrollOffset
        let padding = baseLayout.iconSize / 2 + baseLayout.itemSpacing / 2
        guard along >= centers[first] - padding, along <= centers[last] + padding else { return nil }
        return positions.filter { store.entries[$0].id != sourceID && along > centers[$0] }.count
    }

    /// Uses resting section bounds so insertion previews cannot move the unpin destination.
    /// Includes spacing between running apps and a collapsed running-section control.
    func runningSectionTarget(at point: CGPoint) -> Bool {
        guard !launcher.isPresented, visibility.exposesContent, restingDragBounds.contains(point) else { return false }
        let indices = store.entries.indices.filter { store.entries[$0].appGroup == .running }
        guard let first = indices.first, let last = indices.last,
              last < baseLayout.restingCenters.count else { return false }
        let local = CGPoint(x: point.x - baseRestingFrame.minX, y: baseRestingFrame.maxY - point.y)
        let along = baseLayout.edge.along(local) - interaction.scrollOffset
        return along >= baseLayout.restingCenters[first] - baseLayout.iconSize / 2
            && along <= baseLayout.restingCenters[last] + baseLayout.iconSize / 2
    }

    /// Document hits use the same inverse animation transform and viewport-clipped icons as clicks.
    func documentTarget(at point: CGPoint) -> DockItem? {
        guard !stopped, !launcher.isPresented, panel.frame.contains(point) else { return nil }
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle, progress: visibility.progress,
            size: interaction.layout.viewportSize, reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        return DockDocumentTarget.app(at: contentPoint(point), entries: store.entries, frames: interaction.iconRects,
                                      mask: sample.mask, exposed: visibility.exposesContent)
    }

    /// Melt reserves only the central half of an app icon, leaving pin insertion at its edges.
    func meltTarget(at point: CGPoint) -> DockItem? {
        guard let item = documentTarget(at: point),
              let rect = interaction.iconRects[DockEntryID.app(item.id).hitID],
              rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25).contains(contentPoint(point)) else { return nil }
        return item
    }

    /// Hit test for a trailing utility tile, using the same clipped content space as clicks.
    func utilityTarget(_ entry: DockEntryID, at point: CGPoint) -> Bool {
        guard !stopped, !launcher.isPresented, panel.frame.contains(point), visibility.exposesContent else { return false }
        let sample = DockAnimationGeometry.sample(style: visibility.settings.animationStyle,
            progress: visibility.progress, size: interaction.layout.viewportSize,
            reduceMotion: visibility.reduceMotion, edge: interaction.layout.edge)
        let local = contentPoint(point)
        return sample.mask.contains(local)
            && interaction.iconRects[entry.hitID]?.contains(local) == true
    }

    /// Uses the same animation mask and icon rectangles as native click handling.
    func folderTarget(at point: CGPoint) -> FolderDockItem? {
        store.entries.compactMap { entry -> FolderDockItem? in
            guard case .folder(let folder) = entry, folder.isAvailable,
                  utilityTarget(.folder(folder.reference.id), at: point) else { return nil }
            return folder
        }.first
    }

    /// Pixel density of the screen this dock is on, for artwork generated at native resolution.
    var backingScaleFactor: CGFloat { panel.screen?.backingScaleFactor ?? 2 }

    /// The volume tile under a file drag, using the same mask and icon rectangles as clicks.
    func volumeTarget(at point: CGPoint) -> VolumeDockItem? {
        store.entries.compactMap(\.volume).first { !$0.isEjecting && utilityTarget(.volume($0.volumeID), at: point) }
    }

    func actionTarget(at point: CGPoint) -> ActionDockItem? {
        store.entries.compactMap(\.action).first {
            !$0.status.busy && utilityTarget(.action($0.tile.id), at: point)
        }
    }

    func trashTarget(at point: CGPoint) -> Bool { utilityTarget(.trash, at: point) }
    func shelfTarget(at point: CGPoint) -> Bool { utilityTarget(.shelf, at: point) }

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
        if held { exclusiveInteractionBegan?() }
        pickerHeld = held
        if held { visibility.showImmediately() }
        updatePointer()
    }

    /// Held while any dock popover (a folder stack or the Shelf) is showing over this display.
    func holdPopover(_ held: Bool) {
        // Another dock popover took over; the compact Launcher is one too, so it steps aside.
        if held, compactLauncher != nil { closeActiveLauncher(animated: false, restoreFocus: false) }
        if held { exclusiveInteractionBegan?() }
        popoverHeld = held
        if held { visibility.showImmediately(); interaction.tooltips.clear() }
        updatePointer()
    }

    func holdWindowPeek(_ held: Bool) {
        windowPeekHeld = held
        if held { visibility.showImmediately(); interaction.tooltips.clear() }
        updatePointer()
    }

    /// Held while a volume card is showing over this display, so the dock stays revealed under it.
    func holdVolumeCard(_ held: Bool) {
        guard volumeCardHeld != held else { return }
        volumeCardHeld = held
        if held { visibility.showImmediately(); interaction.tooltips.clear() }
        updatePointer()
    }

    /// The settings this dock last rendered with, or nil before its first update or after stop.
    var currentSettings: DockSettings? { stopped ? nil : lastSettings }

    func holdModePicker(_ held: Bool) {
        modePickerHeld = held
        if held { visibility.showImmediately(); interaction.tooltips.clear() }
        updatePointer()
    }

    func modePickerAnchor() -> DockModePickerAnchor? {
        guard !stopped, let display = lastDisplay, let settings = lastSettings else { return nil }
        let rect = store.selectedTarget.flatMap { interaction.iconRects[$0.hitID] } ?? interaction.surfaceRect
        let screenRect = CGRect(x: panel.frame.minX + interaction.contentOrigin.x + rect.minX,
                                y: panel.frame.maxY - interaction.contentOrigin.y - rect.maxY,
                                width: rect.width, height: rect.height)
        return DockModePickerAnchor(source: screenRect, edge: settings.edge, visibleFrame: display.visibleFrame)
    }

    struct WindowPeekContext {
        let anchor: WindowPeekAnchor
        let settings: DockSettings
    }

    func windowPeekContext(for id: String) -> WindowPeekContext? {
        guard !stopped, let display = lastDisplay, let settings = lastSettings,
              let rect = interaction.iconRects[DockEntryID.app(id).hitID],
              store.items.contains(where: { $0.id == id && $0.isRunning }) else { return nil }
        let screenRect = CGRect(x: panel.frame.minX + interaction.contentOrigin.x + rect.minX,
                                y: panel.frame.maxY - interaction.contentOrigin.y - rect.maxY,
                                width: rect.width, height: rect.height)
        return WindowPeekContext(anchor: WindowPeekAnchor(icon: screenRect, edge: settings.edge,
                                                          visibleFrame: display.visibleFrame),
                                 settings: settings)
    }

    /// The new notification this dock's Line icon label previews for `item`, plus the label itself
    /// while it is on screen, so Window Peek can carry both into its panel. Nil when the tile has no
    /// new badge with a banner.
    func windowPeekNoticeHandoff(for item: DockItem) -> WindowPeekNoticeHandoff? {
        guard !stopped, let badge = DockTooltipBadge(slot: .app(item), interaction: interaction),
              let notice = WindowPeekNotice(badge: badge, appName: item.reference.name) else { return nil }
        let target = DockEntryID.app(item.id)
        var label: WindowPeekNoticeHandoff.Label?
        if interaction.tooltips.visible == target, let presented = interaction.tooltips.presented,
           presented.target == target {
            // Root space to screen, as `windowPeekContext` converts the icon.
            let rect = presented.frame
            let frame = CGRect(x: panel.frame.minX + interaction.contentOrigin.x + rect.minX,
                               y: panel.frame.maxY - interaction.contentOrigin.y - rect.maxY,
                               width: rect.width, height: rect.height)
            label = .init(frame: frame, artwork: presented.artwork)
        }
        return WindowPeekNoticeHandoff(notice: notice, label: label)
    }

    /// Screen-space anchor for a popover attached to one of this dock's tiles.
    func popoverAnchor(for target: DockEntryID) -> DockPopoverAnchor? {
        guard !stopped, let display = lastDisplay, let settings = lastSettings,
              let rect = interaction.iconRects[target.hitID] else { return nil }
        let screenRect = CGRect(x: panel.frame.minX + interaction.contentOrigin.x + rect.minX,
            y: panel.frame.maxY - interaction.contentOrigin.y - rect.maxY,
            width: rect.width, height: rect.height)
        return DockPopoverAnchor(icon: screenRect, edge: settings.edge, visibleFrame: display.visibleFrame)
    }

    /// A tile's frame in AppKit screen coordinates, or `nil` when this dock does not show it or it is
    /// scrolled out of view.
    func tileFrame(for target: DockEntryID) -> CGRect? {
        guard let rect = popoverAnchor(for: target)?.icon, !rect.isNull, !rect.isEmpty else { return nil }
        return rect
    }

    /// Something landed in `target`, such as a picture saved to the Shelf; the tile acknowledges it.
    func tileReceived(_ target: DockEntryID) {
        guard !stopped else { return }
        interaction.arrivals[target.hitID, default: 0] += 1
    }

    func endSectionDrag() { store.sections.endDrag() }

    func setDragPresentation(proposal: DockDragProposal?, source: String?, targeted: Bool, message: LocalizedStringResource?) {
        guard !stopped else { return }
        let previousSlots = DockRenderSlot.slots(entries: store.entries, proposal: interaction.dragProposal)
        let nextSlots = DockRenderSlot.slots(entries: store.entries, proposal: proposal)
        // Moving one preview between boundaries changes slot order, not panel geometry. Avoid
        // synchronously setting the native window frame again from AppKit's drag callback.
        let layoutChanged = previousSlots.count != nextSlots.count
            || previousSlots.filter(\.isPinned).count != nextSlots.filter(\.isPinned).count
        interaction.dragProposal = proposal
        interaction.dragSourceID = source
        interaction.dragActive = source != nil || targeted
        interaction.dragMessage = message
        if source != nil || targeted { exclusiveInteractionBegan?() }
        // Only revealed destinations are held. Hidden targets must still satisfy the configured dwell.
        dragHeld = source != nil || (targeted && visibility.exposesContent)
        if !interaction.dragActive && NSEvent.pressedMouseButtons == 0 { mouseHeld = false }
        if source != nil { visibility.showImmediately() }
        if layoutChanged, let display = lastDisplay, let settings = lastSettings { update(display: display, settings: settings) }
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

    /// Opening is deliberate focus acquisition; hover and ordinary dock geometry remain nonactivating.
    func openLauncher(files: LauncherFileAdoption? = nil) {
        guard !stopped, let display = lastDisplay, let settings = lastSettings else { return }
        if launcher.isPresented {
            guard let files else { closeActiveLauncher(); return }
            // Only the full Launcher offers file actions, so a drop replaces an open compact grid.
            guard compactLauncher != nil else { launcher.adoptFiles(files); return }
            closeActiveLauncher(animated: false, restoreFocus: false)
        }
        let origin = restingDragBounds
        let previousApplication = launcherWillOpen?() ?? NSWorkspace.shared.frontmostApplication
        invalidateDrag?()
        visibility.showImmediately()
        interaction.tooltips.clear()
        interaction.suppressTooltips = true
        let trigger: AnalyticsLauncherSource = files != nil ? .fileDrop : store.keyboardFocus ? .keyboard : .tile
        if files == nil, settings.launcherStyle == .compact, let anchor = restingLauncherAnchor() {
            openCompactLauncher(anchor: anchor, previousApplication: previousApplication)
            Analytics.track(.launcherOpened(trigger, fileCount: 0, style: .compact))
            return
        }
        interaction.exposesContent = false
        interaction.idleFade.update(interacting: true, fullyVisible: true)
        visibility.update(activation: false, retained: true, held: true)
        launcherPresentation.open(origin: origin,
            target: LauncherGeometry.frame(visibleFrame: display.visibleFrame, origin: origin, edge: settings.edge),
            dockWindow: geometry?.windowFrame ?? origin,
            pins: store.pins.compactMap(\.application), previousApplication: previousApplication)
        Analytics.track(.launcherOpened(trigger, fileCount: files?.inputs.count ?? 0, style: .full))
        if let files { launcher.adoptFiles(files) }
    }

    /// Opens the compact grid above the Launcher tile. The dock stays in place and revealed beneath it.
    private func openCompactLauncher(anchor: DockPopoverAnchor, previousApplication: NSRunningApplication?) {
        interaction.idleFade.update(interacting: true, fullyVisible: true)
        visibility.update(activation: false, retained: true, held: true)
        interaction.compactLauncherOpen = true
        let controller = CompactLauncherController(launcher: launcher, anchor: anchor,
                                                   pins: store.pins.compactMap(\.application),
                                                   previousApplication: previousApplication)
        controller.didClose = { [weak self] in
            guard let self else { return }
            compactLauncher = nil
            interaction.compactLauncherOpen = false
            launcherDidClose()
        }
        compactLauncher = controller
        controller.show()
    }

    /// The Launcher tile at rest, in screen space.
    ///
    /// The live tile frame is magnified while the pointer is over it and moves back once the
    /// Launcher opens and clears the pointer, so the compact Launcher's pointer aims at the
    /// resting layout instead. Nil when this dock has no Launcher tile.
    private func restingLauncherAnchor() -> DockPopoverAnchor? {
        guard let display = lastDisplay, let settings = lastSettings,
              let index = store.entries.firstIndex(where: \.isLauncher),
              index < baseLayout.restingCenters.count else { return nil }
        let along = baseLayout.restingCenters[index] - interaction.scrollOffset
        let icon = baseLayout.iconFrame(centerAlong: along, size: baseLayout.iconSize)
        return DockPopoverAnchor(icon: DockEdge.screenRect(icon, in: baseRestingFrame), edge: settings.edge,
                                 visibleFrame: display.visibleFrame)
    }

    /// Closes whichever Launcher style is open. The compact grid always animates through its popover.
    private func closeActiveLauncher(animated: Bool = true, restoreFocus: Bool = true) {
        if let compactLauncher { compactLauncher.close(restoreFocus: restoreFocus) }
        else { launcherPresentation.close(animated: animated, restoreFocus: restoreFocus) }
    }

    /// Returns the dock to its resting frame and input handling after either Launcher style closes.
    private func launcherDidClose() {
        guard !stopped else { return }
        panel.setFrame(geometry?.windowFrame ?? .zero, display: true)
        mouseHeld = false
        updatePointer(); present()
    }

    func closeLauncher() { closeActiveLauncher(animated: false, restoreFocus: false) }

    func owns(_ window: NSWindow?) -> Bool { window === panel }
    /// Rebuilds the panel envelope after timeline browsing starts or ends so the glance card fits.
    func refreshLayout() {
        guard let display = lastDisplay, let settings = lastSettings else { return }
        update(display: display, settings: settings)
    }

    func focus() {
        closeActiveLauncher(animated: false, restoreFocus: false)
        store.keyboardFocus = true
        visibility.showImmediately()
        panel.acceptsKeyboardFocus = true
        store.selectedTarget = store.selectedTarget ?? store.entries.first?.target
        ExplicitWindowPresenter.shared.present(panel)
        panel.makeFirstResponder(panel)
        updatePointer()
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard !launcher.isPresented, store.keyboardFocus else { return false }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           event.charactersIgnoringModifiers == "/" {
            Analytics.track(.focusDockCommand(.windowSearch))
            windowSearchRequested?(); return true
        }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           event.charactersIgnoringModifiers?.lowercased() == "m" {
            Analytics.track(.focusDockCommand(.modePicker))
            modePickerRequested?()
            return true
        }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "o" {
            if let item = store.entries.compactMap(\.item).first(where: { $0.id == store.selectedID }), item.isAvailable {
                Analytics.track(.focusDockCommand(.openFiles))
                interaction.openFiles?(item)
            }
            return true
        }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           event.charactersIgnoringModifiers?.lowercased() == "b" {
            if let item = store.entries.compactMap(\.item).first(where: { $0.id == store.selectedID }) {
                Analytics.track(.focusDockCommand(.badgeMemory))
                interaction.openBadgeMemory?(item)
            }
            return true
        }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            Analytics.track(.focusDockCommand(.history))
            timelineRequested?()
            return true
        }
        if interaction.timeline?.isActive(on: store.displayID) == true {
            if let distance = interaction.layout.edge.navigationStep(keyCode: event.keyCode) {
                interaction.timeline?.nudge(by: distance)
                return true
            }
            if event.keyCode == 53 { escape?(); return true }
            return true
        }
        if let distance = interaction.layout.edge.navigationStep(keyCode: event.keyCode) {
            if event.modifierFlags.contains(.option),
               let pin = store.entries.first(where: { $0.target == store.selectedTarget })?.pin {
                Analytics.track(.focusDockCommand(.movePin))
                Analytics.performing(.keyboard) { store.movePin(pin.id, by: distance) }
            } else {
                store.moveSelection(by: distance)
            }
            return true
        }
        switch event.keyCode {
        case 36, 76:
            Analytics.track(.focusDockCommand(.open))
            Analytics.performing(.keyboard) { store.openSelection() }
        case 49:
            Analytics.track(.focusDockCommand(.windowPeek))
            if case .app(let id) = store.selectedTarget,
               let item = store.items.first(where: { $0.id == id }) { interaction.openWindowPeek?(item) }
            else if case .group = store.selectedTarget { store.openSelection() }
        case 53:
            Analytics.track(.focusDockCommand(.exit))
            escape?()
        default: return false
        }
        return true
    }
    /// The coordinator clears its focus owner before this potentially reentrant resign operation.
    func endFocus() {
        ExplicitWindowPresenter.shared.cancel(panel)
        store.keyboardFocus = false; store.selectedID = nil; panel.acceptsKeyboardFocus = false
        panel.resignKey(); updatePointer()
    }
    /// Sleep cancels the idle deadline; the next display refresh resumes normal input handling.
    func suspendIdleFading() {
        closeActiveLauncher(animated: false, restoreFocus: false)
        idleSuspended = true
        approach.hide()
        interaction.suppressTooltips = true; interaction.tooltips.clear()
        interaction.idleFade.reset()
    }

    func stop() {
        compactLauncher?.didClose = nil; compactLauncher?.close(restoreFocus: false); compactLauncher = nil
        launcherPresentation.stop(); launcherWillOpen = nil; interaction.openLauncher = nil
        invalidateDrag?(); invalidateDrag = nil
        approach.stop()
        stopped = true; interaction.exposesContent = false; interaction.suppressTooltips = true; interaction.tooltips.clear(); interaction.toggleSection = nil; interaction.idleFade.stop(); visibility.stop()
        interaction.sourceTrackingChanged = nil
        interaction.openBadgeMemory = nil
        interaction.prepareSettings = nil; interaction.openFiles = nil; interaction.openFolder = nil; interaction.revealFolder = nil; interaction.stageFolderOnShelf = nil
        interaction.openTrash = nil; interaction.emptyTrash = nil
        interaction.openVolume = nil; interaction.revealVolume = nil; interaction.ejectVolume = nil
        interaction.volumeHoverChanged = nil; interaction.beginVolumeDrag = nil
        interaction.hideVolume = nil; interaction.prepareVolumeSettings = nil
        interaction.canMoveVolume = nil; interaction.moveVolume = nil
        interaction.openFocusSession = nil
        interaction.openSessionCapsules = nil; interaction.openSessionCapsule = nil
        interaction.openNotificationFeed = nil; interaction.notificationFeed = nil
        interaction.clearNotificationFeed = nil; interaction.prepareNotificationFeedSettings = nil
        interaction.resumeSessionCapsule = nil; interaction.deleteSessionCapsule = nil
        interaction.windowPeekHoverChanged = nil; interaction.openWindowPeek = nil
        interaction.removePin = nil; interaction.setFolderPresentation = nil
        interaction.beginDrag = nil; interaction.movePin = nil; interaction.canMovePin = nil
        interaction.beginFolderDrag = nil
        interaction.moveUtility = nil; interaction.canMoveUtility = nil; interaction.beginUtilityDrag = nil
        interaction.copyPin = nil; interaction.scrollChanged = nil
        panel.contentView?.unregisterDraggedTypes()
        interaction.stopGeometryUpdates()
        interaction.geometryDidChange = nil; interaction.menuTrackingChanged = nil; interaction.accessibilityFocusChanged = nil
        panel.resignedKey = nil; panel.keyboardHandler = nil; resignedFocus = nil; escape = nil; exclusiveInteractionBegan = nil
        timelineRequested = nil
        interaction.timeline = nil
        interaction.sims = nil
        windowSearchRequested = nil
        modePickerRequested = nil
        accessibilityIDs.removeAll(); mouseHeld = false; menuHeld = false; dragHeld = false; popoverHeld = false; windowPeekHeld = false; volumeCardHeld = false; modePickerHeld = false
        store.stop(); panel.close(); panel.contentView = nil
    }
}
