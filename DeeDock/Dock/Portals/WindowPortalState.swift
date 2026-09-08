import AppKit
import Observation
import SwiftUI

nonisolated enum WindowPortalPhase: Equatable {
    case connecting, live, paused, userPaused, frozen, reselect, unavailable, stale, permissionRequired

    var label: LocalizedStringResource {
        switch self {
        case .connecting: .portalConnecting
        case .live: .portalLive
        case .paused: .portalPaused
        case .userPaused: .portalUserPaused
        case .frozen: .portalFrozen
        case .reselect: .portalReselect
        case .unavailable: .portalUnavailable
        case .stale: .portalStale
        case .permissionRequired: .portalPermission
        }
    }

    /// The one glyph that states what the portal is doing, next to the phase's own words.
    var symbol: String {
        switch self {
        case .connecting: "arrow.triangle.2.circlepath"
        case .live: "dot.radiowaves.left.and.right"
        case .paused, .userPaused: "pause.circle.fill"
        case .frozen: "snowflake"
        case .reselect: "crop"
        case .unavailable: "exclamationmark.triangle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .permissionRequired: "lock.fill"
        }
    }

    /// Green reads as running, orange as needing attention, and everything else stays quiet.
    var color: Color {
        switch self {
        case .live: .green
        case .connecting, .paused, .userPaused: .secondary
        case .frozen: .cyan
        case .reselect, .stale: .orange
        case .unavailable, .permissionRequired: .red
        }
    }

    /// True while a frame is arriving on its own; the pill then pulses instead of sitting still.
    var isStreaming: Bool { self == .live || self == .connecting }
}

/// Ephemeral presentation state; retains at most the latest image and no captured content on disk.
@MainActor @Observable
final class WindowPortalState {
    let appName: String
    /// The source application's icon, used to tint the portal in its own app's color.
    let icon: NSImage?
    var source: ApplicationWindowSummary
    var image: CGImage?
    var phase: WindowPortalPhase = .connecting
    var userPaused = false
    var frozen = false
    var editingCrop = false
    var needsReselection = false
    var crop = NormalizedWindowRegion()
    var cropSourceSize: CGSize?
    var zoom: Double = 1
    var panX: Double = 0.5
    var panY: Double = 0.5

    /// Zoom selects a bounded subrectangle of the crop; pan values run from leading/top to trailing/bottom.
    var viewport: CGRect {
        let rect = crop.rect
        let factor = min(max(zoom, 1), 4)
        let width = rect.width / factor
        let height = rect.height / factor
        return CGRect(x: rect.minX + (rect.width - width) * min(max(panX, 0), 1),
                      y: rect.minY + (rect.height - height) * min(max(panY, 0), 1),
                      width: width, height: height)
    }

    func resetZoom() { zoom = 1; panX = 0.5; panY = 0.5 }

    func applyCrop(_ region: NormalizedWindowRegion) {
        crop = region.clamped
        cropSourceSize = crop == NormalizedWindowRegion() ? nil : source.frame?.size
        needsReselection = false
        editingCrop = false
        resetZoom()
        phase = frozen ? .frozen : (userPaused ? .userPaused : .connecting)
    }
    var lastFrameAt: Date?
    var captures = 0
    var captureMilliseconds = 0.0
    var jumpFailed = false
    /// Set when a save was attempted and no file was written, so the panel can say so.
    var exportFailed = false
    @ObservationIgnored var freeze: (() -> Void)?
    @ObservationIgnored var editCrop: (() -> Void)?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var jump: (() -> Void)?
    @ObservationIgnored var togglePause: (() -> Void)?
    @ObservationIgnored var saveFrame: (() -> Void)?
    @ObservationIgnored var move: ((CGFloat, CGFloat) -> Void)?

    var sourceName: String {
        source.title?.isEmpty == false ? "\(appName): \(source.title!)" : appName
    }

    init(appName: String, source: ApplicationWindowSummary, icon: NSImage? = nil) {
        self.appName = appName
        self.source = source
        self.icon = icon
    }
}

/// AppKit global points, including negative display origins. Keep the whole portal on a usable screen.
nonisolated enum WindowPortalGeometry {
    static func clamped(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}
