import CoreGraphics
import ScreenCaptureKit

/// Shared one-shot capture for Peek and portals. Call from a capture actor, never a rendering path.
nonisolated enum WindowScreenshot {
    static func capture(_ window: SCWindow, fittingPixels size: CGSize) async throws -> CGImage {
        let source = window.frame.size
        let scale = min(size.width / max(1, source.width), size.height / max(1, source.height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((source.width * scale).rounded()))
        configuration.height = max(1, Int((source.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
    }
}
