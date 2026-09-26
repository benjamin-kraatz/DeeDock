import CoreGraphics
import ScreenCaptureKit

/// Shared one-shot capture for Peek and portals. Call from a capture actor, never a rendering path.
nonisolated enum WindowScreenshot {
    /// Converts a logical point size into backing pixels.
    ///
    /// A non-positive `pointPixelScale` is treated as 1×. A missing scale must not collapse the budget to nothing.
    static func backingPixels(for logical: CGSize, pointPixelScale: CGFloat) -> CGSize {
        let scale = max(pointPixelScale, 1)
        return CGSize(width: (logical.width * scale).rounded(),
                      height: (logical.height * scale).rounded())
    }

    /// Pixel size of a window frame fitted inside an exact pixel budget, preserving aspect ratio.
    ///
    /// The result is at least 1×1. Callers that already hold pixels (portals, atmosphere, the enlarged
    /// preview) pass that budget through; this function does not apply another display scale.
    static func outputPixels(source: CGSize, fittingPixels budget: CGSize) -> CGSize {
        let fit = min(budget.width / max(1, source.width), budget.height / max(1, source.height))
        return CGSize(width: max(1, (source.width * fit).rounded()),
                      height: max(1, (source.height * fit).rounded()))
    }

    static func capture(_ window: SCWindow, fittingPixels size: CGSize) async throws -> CGImage {
        try await capture(filter: SCContentFilter(desktopIndependentWindow: window),
                          source: window.frame.size, fittingPixels: size)
    }

    /// Captures `source` (the window frame, in points) fitted into `size` pixels.
    ///
    /// `.best` asks for the display's full resolution. The automatic resolution returns a Retina
    /// window at its point size, so a 2× card would be stored with half the pixels. Callers pass
    /// `.automatic` only as a compatibility choice for displays where `.best` misbehaves.
    static func capture(filter: SCContentFilter, source: CGSize, fittingPixels size: CGSize,
                        resolution: SCCaptureResolutionType = .best) async throws -> CGImage {
        let pixels = outputPixels(source: source, fittingPixels: size)
        let configuration = SCStreamConfiguration()
        configuration.captureResolution = resolution
        configuration.width = max(1, Int(pixels.width))
        configuration.height = max(1, Int(pixels.height))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = false
        try Task.checkCancellation()
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
