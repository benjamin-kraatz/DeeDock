import Foundation
import CoreGraphics
import ScreenCaptureKit

nonisolated enum WindowPortalCaptureResult: Sendable {
    case frame(CGImage, ApplicationWindowSummary)
    case paused
    case permissionRequired
    case unavailable
    case stale
}

/// One portal owns one binding. A missing bound ID is terminal; title or geometry changes never rebind it.
actor WindowPortalCapture {
    private let source: ApplicationWindowSummary
    private var boundWindow: SCWindow?
    private var lostSource = false

    init(source: ApplicationWindowSummary) { self.source = source }

    /// Resolve current metadata by the bound ID before a deliberate jump, including off-screen sources.
    func currentSource() async -> ApplicationWindowSummary? {
        guard !lostSource, let id = boundWindow?.windowID, CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            guard !lostSource, let window = content.windows.first(where: {
                $0.windowID == id && $0.owningApplication?.processID == source.processIdentifier
            }) else { return nil }
            return ApplicationWindowSummary(token: source.token, processIdentifier: source.processIdentifier,
                title: window.title, frame: window.frame, isMinimized: !window.isOnScreen, isMain: false)
        } catch { return nil }
    }

    func update(pixelSize: CGSize) async -> WindowPortalCaptureResult {
        guard !lostSource else { return .unavailable }
        guard CGPreflightScreenCaptureAccess() else { return .permissionRequired }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            let windows = content.windows.filter {
                $0.owningApplication?.processID == source.processIdentifier
                    && source.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0
            }
            if boundWindow == nil {
                let candidates = windows.map {
                    WindowCaptureCandidate(id: $0.windowID, processIdentifier: source.processIdentifier,
                                           title: $0.title, frame: $0.frame, isOnScreen: $0.isOnScreen)
                }
                guard let id = WindowThumbnailMatcher.matches(summaries: [source], candidates: candidates)[source.token],
                      let window = windows.first(where: { $0.windowID == id }) else {
                    lostSource = true
                    return .unavailable
                }
                boundWindow = window
            }
            guard let window = windows.first(where: { $0.windowID == boundWindow?.windowID }) else {
                lostSource = true
                boundWindow = nil
                return .unavailable
            }
            // Off-screen includes minimized and other-Space windows; public metadata cannot distinguish them.
            guard window.isOnScreen else { return .paused }
            let image = try await WindowScreenshot.capture(window, fittingPixels: pixelSize)
            try Task.checkCancellation()
            return .frame(image, ApplicationWindowSummary(token: source.token,
                processIdentifier: source.processIdentifier, title: window.title, frame: window.frame,
                isMinimized: false, isMain: false))
        } catch { return .stale }
    }
}
