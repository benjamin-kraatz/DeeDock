import CoreGraphics
import ScreenCaptureKit

/// Serializes bounded, in-memory captures away from the main actor. No image is saved or shared.
actor AtmosphereWindowLightCapture {
    private var capturing = false

    func colors(windowID: CGWindowID, pid: pid_t, mode: AtmosphereWindowLightMode) async -> [AtmosphereColor]? {
        guard !capturing, CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return nil }
        capturing = true
        defer { capturing = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard !Task.isCancelled, let window = content.windows.first(where: {
                $0.windowID == windowID && $0.owningApplication?.processID == pid
            }) else { return nil }
            let image = try await WindowScreenshot.capture(window, fittingPixels: CGSize(width: 64, height: 64))
            guard !Task.isCancelled,
                  let palette = AtmospherePaletteSampler.sample(image, mode: mode == .average ? .average : .gradient) else { return nil }
            return AtmosphereWindowLightPalette.softened(palette.first)
        } catch { return nil }
    }
}
