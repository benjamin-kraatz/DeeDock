import AppKit
import CoreImage

/// The drag image for an item the sensitive guard flagged: its preview blurred past reading, with a
/// lock, as its row and the dock tile draw it. A drag shows the file under the pointer in front of
/// other apps, so a blurred row alone would not keep an ID or bank details off screen.
@MainActor
enum FlixSensitiveImage {
    /// `image` blurred, with a lock over its middle. Falls back to the image itself when Core
    /// Image cannot render it. Runs once at drag start, on an icon of at most a few hundred points.
    static func blurred(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let input = CIImage(cgImage: cgImage)
        let radius = max(6, Double(min(cgImage.width, cgImage.height)) / 9)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let blurred = CIContext().createCGImage(output, from: input.extent) else { return image }
        let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: max(10, size.width / 4), weight: .semibold))
        return NSImage(size: size, flipped: false) { rect in
            NSImage(cgImage: blurred, size: size).draw(in: rect)
            if let lock {
                let side = lock.size
                let origin = CGPoint(x: rect.midX - side.width / 2, y: rect.midY - side.height / 2)
                NSColor.white.withAlphaComponent(0.9).set()
                lock.draw(in: CGRect(origin: origin, size: side), from: .zero, operation: .sourceOver, fraction: 0.9)
            }
            return true
        }
    }
}
