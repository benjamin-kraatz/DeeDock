import CoreGraphics
import Foundation
import Observation

/// Per-panel geometry shared between SwiftUI presentation and AppKit pointer handling.
@MainActor @Observable
final class DockInteraction {
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
