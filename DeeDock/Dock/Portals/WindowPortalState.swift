import AppKit
import Observation

nonisolated enum WindowPortalPhase: Equatable {
    case connecting, live, paused, unavailable, stale, permissionRequired

    var label: LocalizedStringResource {
        switch self {
        case .connecting: .portalConnecting
        case .live: .portalLive
        case .paused: .portalPaused
        case .unavailable: .portalUnavailable
        case .stale: .portalStale
        case .permissionRequired: .portalPermission
        }
    }
}

/// Ephemeral presentation state; retains at most the latest image and no captured content on disk.
@MainActor @Observable
final class WindowPortalState {
    let appName: String
    var source: ApplicationWindowSummary
    var image: CGImage?
    var phase: WindowPortalPhase = .connecting
    var userPaused = false
    var lastFrameAt: Date?
    var captures = 0
    var captureMilliseconds = 0.0
    var jumpFailed = false
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var jump: (() -> Void)?
    @ObservationIgnored var togglePause: (() -> Void)?
    @ObservationIgnored var move: ((CGFloat, CGFloat) -> Void)?

    var sourceName: String {
        source.title?.isEmpty == false ? "\(appName): \(source.title!)" : appName
    }

    init(appName: String, source: ApplicationWindowSummary) {
        self.appName = appName
        self.source = source
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
