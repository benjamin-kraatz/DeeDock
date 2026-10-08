import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Loads a display's wallpaper and blurs it once for Harbor's backdrop.
///
/// The image is decoded at a quarter of the display's pixel width; the blur hides the lost detail
/// and the backdrop then costs one static layer rather than a live full-screen blur. Results are
/// cached per wallpaper file, modification date, and size, so reopening Harbor is instant.
///
/// `NSWorkspace.desktopImageURL(for:)` covers still and time-of-day wallpapers. Aerial and other
/// video wallpapers may report no usable file; callers then fall back to a plain backdrop.
actor HarborWallpaperLoader {
    private nonisolated struct Key: Hashable {
        let url: URL
        let modified: Date?
        let width: Int
        let height: Int
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private var cache: [Key: CGImage] = [:]

    /// - Parameters:
    ///   - url: The wallpaper file for the display.
    ///   - displaySize: The display's size in points; the image is filled into it.
    ///   - scale: The display's backing scale.
    func backdrop(url: URL, displaySize: CGSize, scale: CGFloat) -> CGImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = Key(url: url, modified: modified, width: Int(displaySize.width), height: Int(displaySize.height))
        if let cached = cache[key] { return cached }
        let maximum = max(displaySize.width, displaySize.height) * max(scale, 1) / 4
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maximum)),
              ] as CFDictionary) else { return nil }
        // The view fills the display with this image, so one image pixel spans this many points.
        let pointsPerPixel = max(displaySize.width / CGFloat(image.width), displaySize.height / CGFloat(image.height))
        let sigma = HarborStyle.backdropBlur / max(pointsPerPixel, 0.01) / 2
        let input = CIImage(cgImage: image)
        // Clamping before the blur keeps the edges from fading to transparent.
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
            .cropped(to: input.extent)
        guard let blurred = Self.context.createCGImage(output, from: input.extent) else { return nil }
        // A changed wallpaper replaces its older entry for the same display size.
        cache = cache.filter { $0.key.url != url || $0.key.width != key.width || $0.key.height != key.height }
        if cache.count >= 8 { cache.removeAll() }
        cache[key] = blurred
        return blurred
    }
}
