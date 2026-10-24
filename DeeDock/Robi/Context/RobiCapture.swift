import AppKit
import ScreenCaptureKit
import Vision

/// One-shot captures of the window Robi sits on, and text recognition in them.
///
/// Only the target window is captured (`desktopIndependentWindow`), so Robi's own panels and
/// anything overlapping the window never appear. Pictures stay in memory for one request.
actor RobiCapture {
    /// Longest side of a captured picture. Fits Claude's recommended 1,568 px with a little slack
    /// and keeps the on-device model's image cost down.
    static let maximumPixels: CGFloat = 1_568
    private var prewarmed = false

    /// The window, or a region of it in window-local top-left points.
    func image(windowID: CGWindowID, region: CGRect? = nil) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), let window = await Self.window(windowID) else { return nil }
        let source = region ?? CGRect(origin: .zero, size: window.frame.size)
        guard source.width >= 1, source.height >= 1 else { return nil }
        let scale = min(2, Self.maximumPixels / max(source.width, source.height))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = max(1, Int(source.width * scale))
        configuration.height = max(1, Int(source.height * scale))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                           configuration: configuration)
    }

    /// The median colour of a thin strip just under the window's top edge, across the tab's
    /// footprint. Sampling under the tab matters: Chromium's tab strip, for one, has a different
    /// colour behind the active tab than in the middle.
    func tint(windowID: CGWindowID, footprint: ClosedRange<CGFloat>) async -> NSColor? {
        guard CGPreflightScreenCaptureAccess(), let window = await Self.window(windowID) else { return nil }
        let lower = max(0, footprint.lowerBound), upper = min(window.frame.width, footprint.upperBound)
        guard upper - lower >= 8 else { return nil }
        let configuration = SCStreamConfiguration()
        // Two points down skips the window's rim highlight; five points stay above title text.
        configuration.sourceRect = CGRect(x: lower, y: 2, width: upper - lower, height: 5)
        configuration.width = Int((upper - lower) * 2)
        configuration.height = 10
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                     configuration: configuration) else { return nil }
        return Self.median(image)
    }

    func recognizeText(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return "" }
        return observations.map(\.transcript).joined(separator: "\n")
    }

    /// The first recognition in a process loads Vision's models, which took 13–27 s in the spike;
    /// later ones take about 50–150 ms. Run once in the background when Robi is turned on.
    func prewarm() async {
        guard !prewarmed else { return }
        prewarmed = true
        let size = CGSize(width: 160, height: 36)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 12, y: 12, width: 40, height: 12))
        guard let image = context.makeImage() else { return }
        _ = await recognizeText(image)
    }

    private static func window(_ id: CGWindowID) async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        return content.windows.first { $0.windowID == id }
    }

    private static func median(_ image: CGImage) -> NSColor? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var red: [UInt8] = [], green: [UInt8] = [], blue: [UInt8] = []
        red.reserveCapacity(width * height); green.reserveCapacity(width * height); blue.reserveCapacity(width * height)
        for index in stride(from: 0, to: data.count, by: 4) {
            red.append(data[index]); green.append(data[index + 1]); blue.append(data[index + 2])
        }
        func middle(_ values: [UInt8]) -> CGFloat { CGFloat(values.sorted()[values.count / 2]) / 255 }
        return NSColor(srgbRed: middle(red), green: middle(green), blue: middle(blue), alpha: 1)
    }
}
