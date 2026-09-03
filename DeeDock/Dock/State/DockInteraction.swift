import AppKit
import Foundation
import Observation

/// Per-panel geometry shared between SwiftUI presentation and AppKit pointer handling.
@MainActor @Observable
final class DockInteraction {
    var dragProposal: DockDragProposal?
    var dragActive = false
    var dragSourceID: String?
    var dragMessage: LocalizedStringResource?
    var scrollOffset: CGFloat = 0
    var scrollRequest: CGFloat = 0
    /// Selects this panel's display before SwiftUI opens the Settings scene.
    @ObservationIgnored var prepareSettings: (() -> Void)?
    @ObservationIgnored var sourceTrackingChanged: ((Bool) -> Void)?
    @ObservationIgnored var beginDrag: ((DockItem, NSView, NSEvent) -> Void)?
    @ObservationIgnored var movePin: ((String, Int) -> Void)?
    @ObservationIgnored var canMovePin: ((String, Int) -> Bool)?
    @ObservationIgnored var copyPin: ((ApplicationReference, String) -> Void)?
    var pinDestinations: [DockPinDestination] = []
    @ObservationIgnored var scrollChanged: (() -> Void)?
    var contentOrigin = CGPoint.zero
    var windowSize = CGSize(width: 800, height: 248)
    @ObservationIgnored var menuTrackingChanged: ((Bool) -> Void)?
    @ObservationIgnored var accessibilityFocusChanged: ((String, Bool) -> Void)?

    /// Current resting layout for this panel’s ordered items and display width.
    var layout = DockGeometry.layout(count: 0, favoriteCount: 0, availableWidth: 800)
    /// Pointer in panel-local, top-left-origin points; nil outside the surface and exposed app buttons.
    var pointer: CGPoint?
    /// Re-evaluates click passthrough when painted regions change under a stationary pointer.
    @ObservationIgnored var geometryDidChange: (() -> Void)?
    /// Painted dock bounds in panel-local, top-left-origin points, clipped to the viewport.
    @ObservationIgnored var surfaceRect = CGRect.zero {
        didSet { geometryDidChange?() }
    }
    /// Separate icon bounds preserve clicks above the glass without capturing empty space between apps.
    @ObservationIgnored private(set) var iconRects: [String: CGRect] = [:]

    /// Updates a viewport-clipped button frame; nil removes a disappearing app's hit region.
    func setIconRect(_ rect: CGRect?, for id: String) {
        guard iconRects[id] != rect else { return }
        iconRects[id] = rect
        geometryDidChange?()
    }

    /// Whether a panel-local point reaches the glass or an exposed application button.
    func containsDockPoint(_ point: CGPoint) -> Bool {
        surfaceRect.contains(point) || iconRects.values.contains { $0.contains(point) }
    }

    /// Error-banner hit region in the same coordinates; zero when no banner is visible.
    @ObservationIgnored var errorRect = CGRect.zero {
        didSet { geometryDidChange?() }
    }
}
