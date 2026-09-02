import CoreGraphics
import Foundation
import Observation

/// Per-panel geometry shared between SwiftUI presentation and AppKit pointer handling.
@MainActor @Observable
final class DockInteraction {
    /// Current resting layout for this panel’s ordered items and display width.
    var layout = DockGeometry.layout(count: 0, favoriteCount: 0, availableWidth: 800)
    /// Pointer in panel-local, top-left-origin points; nil outside the painted dock surface.
    var pointer: CGPoint?
    /// Re-evaluates click passthrough when painted regions change under a stationary pointer.
    @ObservationIgnored var geometryDidChange: (() -> Void)?
    /// Painted dock bounds in panel-local, top-left-origin points, clipped to the viewport.
    @ObservationIgnored var surfaceRect = CGRect.zero {
        didSet { geometryDidChange?() }
    }
    /// Error-banner hit region in the same coordinates; zero when no banner is visible.
    @ObservationIgnored var errorRect = CGRect.zero {
        didSet { geometryDidChange?() }
    }
}
