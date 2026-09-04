import AppKit
import Foundation
import Observation

/// Per-panel geometry shared between SwiftUI presentation and AppKit pointer handling.
@MainActor @Observable
final class DockInteraction {
    /// Owns this panel's idle deadline and artwork opacity.
    @ObservationIgnored var actionTiles: ActionTilesController?
    let tooltips = DockTooltipController()
    var tooltipPreset: DockTooltipPreset = .classic
    var suppressTooltips = false
    @ObservationIgnored var toggleSection: (() -> Void)?
    let idleFade = DockIdleFadeController()
    /// Per-display running marker appearance, separate from layout and keyboard focus.
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot
    /// The saved preference for animated shader indicators.
    var animateIndicators = DockSettings.defaults.animateIndicators
    /// Whether this panel currently paints anything. A hidden dock schedules no indicator
    /// frames; the owner keeps this in step with the visibility controller.
    var exposesContent = true
    var dragProposal: DockDragProposal?
    var dragActive = false
    var dragSourceID: String?
    var dragMessage: LocalizedStringResource?
    var documentTargetID: String?
    var trashTargeted = false
    var shelfTargeted = false
    var springEmphasized = false
    @ObservationIgnored var openFiles: ((DockItem) -> Void)?
    @ObservationIgnored var applicationMenuSnapshot: ((DockItem) -> ApplicationMenuSnapshot)?
    @ObservationIgnored var beginApplicationWindowDiscovery: ((DockItem, ApplicationMenuSnapshot, @escaping (ApplicationWindowMenuState) -> Void) -> UUID?)?
    @ObservationIgnored var cancelApplicationWindowDiscovery: ((UUID) -> Void)?
    @ObservationIgnored var performApplicationMenuAction: ((ApplicationMenuAction, DockItem) -> Void)?
    @ObservationIgnored var windowPeekHoverChanged: ((DockItem?) -> Void)?
    @ObservationIgnored var openWindowPeek: ((DockItem) -> Void)?
    @ObservationIgnored var openFolder: ((FolderDockItem, Bool) -> Void)?
    @ObservationIgnored var revealFolder: ((FolderDockItem) -> Void)?
    /// Per-display policy for DeeDock's own Empty Trash warning.
    var confirmsTrashEmpty = DockSettings.defaults.confirmBeforeEmptyingTrash
    @ObservationIgnored var openTrash: (() -> Void)?
    @ObservationIgnored var emptyTrash: (() -> Void)?
    @ObservationIgnored var openShelf: (() -> Void)?
    @ObservationIgnored var openSessionCapsules: (() -> Void)?
    @ObservationIgnored var openSessionCapsule: ((UUID) -> Void)?
    @ObservationIgnored var resumeSessionCapsule: ((UUID) -> Void)?
    @ObservationIgnored var deleteSessionCapsule: ((UUID) -> Void)?
    @ObservationIgnored var clearShelf: (() -> Void)?
    @ObservationIgnored var beginShelfDrag: ((NSView, NSEvent) -> Void)?
    @ObservationIgnored var removePin: ((String) -> Void)?
    @ObservationIgnored var setFolderPresentation: ((UUID, FolderStackPresentation) -> Void)?
    var scrollOffset: CGFloat = 0
    var scrollRequest: CGFloat = 0
    /// Selects this panel's display before SwiftUI opens the Settings scene.
    @ObservationIgnored var prepareSettings: (() -> Void)?
    @ObservationIgnored var sourceTrackingChanged: ((Bool) -> Void)?
    @ObservationIgnored var beginDrag: ((DockItem, NSView, NSEvent) -> Void)?
    @ObservationIgnored var beginFolderDrag: ((FolderDockItem, NSView, NSEvent) -> Void)?
    @ObservationIgnored var movePin: ((String, Int) -> Void)?
    @ObservationIgnored var canMovePin: ((String, Int) -> Bool)?
    @ObservationIgnored var copyPin: ((DockPin, String) -> Void)?
    var pinDestinations: [DockPinDestination] = []
    @ObservationIgnored var scrollChanged: (() -> Void)?
    var contentOrigin = CGPoint.zero
    var windowSize = CGSize(width: 800, height: 248)
    @ObservationIgnored var menuTrackingChanged: ((Bool) -> Void)?
    @ObservationIgnored var accessibilityFocusChanged: ((String, Bool) -> Void)?

    /// Current resting layout for this panel’s ordered items and display width.
    var layout = DockGeometry.layout(count: 0, favoriteCount: 0, availableLength: 800)
    /// Pointer in panel-local, top-left-origin points; nil outside the surface and exposed app buttons.
    var pointer: CGPoint?
    /// Re-evaluates click passthrough when painted regions change under a stationary pointer.
    @ObservationIgnored var geometryDidChange: (() -> Void)?
    /// Canvas-space frames published once per layout turn for tooltip placement.
    private(set) var renderedFrames: [DockEntryID: CGRect] = [:]
    @ObservationIgnored private var pendingRenderedFrames: [DockEntryID: CGRect] = [:]
    @ObservationIgnored private var geometryRefreshTask: Task<Void, Never>?
    /// Painted dock bounds in panel-local, top-left-origin points, clipped to the viewport.
    @ObservationIgnored var surfaceRect = CGRect.zero {
        didSet {
            if oldValue != surfaceRect { scheduleGeometryRefresh() }
        }
    }
    /// Separate icon bounds preserve clicks above the glass without capturing empty space between apps.
    @ObservationIgnored private var acceptedHitIDs: Set<String>?
    @ObservationIgnored private(set) var iconRects: [String: CGRect] = [:]

    /// Updates a viewport-clipped button frame; nil removes a disappearing app's hit region.
    func setIconRect(_ rect: CGRect?, for id: String) {
        guard rect == nil || acceptedHitIDs?.contains(id) != false else { return }
        guard iconRects[id] != rect else { return }
        iconRects[id] = rect
        scheduleGeometryRefresh()
    }

    /// Collects tooltip geometry without feeding every animated icon frame back into SwiftUI.
    func setRenderedFrame(_ frame: CGRect?, for target: DockEntryID) {
        guard frame == nil || acceptedHitIDs?.contains(target.hitID) != false else { return }
        guard pendingRenderedFrames[target] != frame else { return }
        pendingRenderedFrames[target] = frame
        scheduleGeometryRefresh()
    }

    /// Removed entries stop capturing clicks immediately, including while their exit artwork animates.
    func retainHitRegions(_ ids: Set<String>) {
        acceptedHitIDs = ids
        let retainedIconRects = iconRects.filter { ids.contains($0.key) }
        let retainedRenderedFrames = pendingRenderedFrames.filter { ids.contains($0.key.hitID) }
        guard retainedIconRects != iconRects || retainedRenderedFrames != pendingRenderedFrames else { return }
        iconRects = retainedIconRects
        pendingRenderedFrames = retainedRenderedFrames
        scheduleGeometryRefresh()
    }

    /// Invalidates old hit regions before the panel changes coordinate systems.
    func resetGeometry() {
        setPointer(nil)
        iconRects.removeAll()
        pendingRenderedFrames.removeAll()
        surfaceRect = .zero
        errorRect = .zero
        scheduleGeometryRefresh()
    }

    /// Avoids invalidating the dock again when geometry resamples the same native pointer event.
    func setPointer(_ point: CGPoint?) {
        if pointer != point { pointer = point }
    }

    /// Whether a panel-local point reaches the glass or an exposed application button.
    func containsDockPoint(_ point: CGPoint) -> Bool {
        surfaceRect.contains(point) || iconRects.values.contains { $0.contains(point) }
    }

    /// Error-banner hit region in the same coordinates; zero when no banner is visible.
    @ObservationIgnored var errorRect = CGRect.zero {
        didSet {
            if oldValue != errorRect { scheduleGeometryRefresh() }
        }
    }

    /// Cancels the deferred geometry publication owned by this panel.
    func stopGeometryUpdates() {
        geometryRefreshTask?.cancel()
        geometryRefreshTask = nil
    }

    private func scheduleGeometryRefresh() {
        guard geometryRefreshTask == nil else { return }
        // SwiftUI reports each magnifying entry separately during layout. Publish their latest
        // frames together after that pass so pointer resampling cannot recursively start layout.
        geometryRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            geometryRefreshTask = nil
            if renderedFrames != pendingRenderedFrames {
                renderedFrames = pendingRenderedFrames
            }
            geometryDidChange?()
        }
    }
}
