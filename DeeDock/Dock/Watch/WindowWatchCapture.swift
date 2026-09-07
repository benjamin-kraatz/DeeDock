import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

nonisolated enum WindowWatchFailure: Error {
    case permission, unavailable, closed, offscreen
}

nonisolated struct WindowWatchFrame: Sendable {
    let image: CGImage
    let pixels: [UInt8]
    let lines: [String]
    let size: CGSize
    let pixelSize: CGSize
}

/// Retains the selected SCWindow and never repeats the title/geometry join after preparation.
/// All raster processing and OCR run on this actor, outside UI and pointer handling.
actor WindowWatchCapture {
    private var window: SCWindow?
    private var pid: pid_t?

    func prepare(_ summary: ApplicationWindowSummary) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw WindowWatchFailure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        let candidates = content.windows.filter { $0.windowLayer == 0 }.map {
            WindowCaptureCandidate(id: $0.windowID, processIdentifier: $0.owningApplication?.processID ?? -1,
                                   title: $0.title, frame: $0.frame, isOnScreen: $0.isOnScreen)
        }
        guard let id = WindowThumbnailMatcher.matches(summaries: [summary], candidates: candidates)[summary.token],
              let selected = content.windows.first(where: { $0.windowID == id }) else {
            throw WindowWatchFailure.unavailable
        }
        window = selected
        pid = summary.processIdentifier
    }

    /// Resolves an explicit jump against the fixed capture identity; ambiguous AX matches fail closed.
    func sourceToken(in summaries: [ApplicationWindowSummary]) async throws -> ApplicationWindowToken {
        guard let window, let pid else { throw WindowWatchFailure.closed }
        guard CGPreflightScreenCaptureAccess() else { throw WindowWatchFailure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let current = content.windows.first(where: { $0.windowID == window.windowID && $0.owningApplication?.processID == pid }) else {
            throw WindowWatchFailure.closed
        }
        let candidate = WindowCaptureCandidate(id: current.windowID, processIdentifier: pid,
                                               title: current.title, frame: current.frame, isOnScreen: current.isOnScreen)
        let matches = WindowThumbnailMatcher.matches(summaries: summaries, candidates: [candidate])
        guard matches.count == 1, let token = matches.keys.first else { throw WindowWatchFailure.unavailable }
        return token
    }

    func sample(region: WindowWatchRegion, recognizeText: Bool, isAppHidden: Bool = false) async throws -> WindowWatchFrame {
        guard CGPreflightScreenCaptureAccess() else { throw WindowWatchFailure.permission }
        guard let window, let pid else { throw WindowWatchFailure.closed }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let current = content.windows.first(where: { $0.windowID == window.windowID && $0.owningApplication?.processID == pid }) else {
            throw WindowWatchFailure.closed
        }
        guard current.isOnScreen, !isAppHidden else { throw WindowWatchFailure.offscreen }
        let filter = SCContentFilter(desktopIndependentWindow: current)
        let scale = min(Double(filter.pointPixelScale), 1600 / max(current.frame.width, current.frame.height, 1))
        let config = SCStreamConfiguration()
        config.width = max(1, Int(current.frame.width * scale))
        config.height = max(1, Int(current.frame.height * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        // CGImage cropping uses raster coordinates, matching the top-left SwiftUI preview.
        let rect = region.rect
        let cropRect = CGRect(x: rect.minX * Double(image.width), y: rect.minY * Double(image.height),
                              width: rect.width * Double(image.width), height: rect.height * Double(image.height)).integral
        guard let crop = image.cropping(to: cropRect) else { throw WindowWatchFailure.unavailable }
        var bytes = [UInt8](repeating: 0, count: 96 * 96)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 96, height: 96,
                                          bitsPerComponent: 8, bytesPerRow: 96,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 96, height: 96))
            return true
        }
        guard rendered else { throw WindowWatchFailure.unavailable }
        var lines: [String] = []
        if recognizeText {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false
            lines = try await request.perform(on: crop).prefix(128).map { String($0.transcript.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        try Task.checkCancellation()
        return WindowWatchFrame(image: image, pixels: bytes, lines: lines, size: current.frame.size,
                                pixelSize: CGSize(width: image.width, height: image.height))
    }
}
