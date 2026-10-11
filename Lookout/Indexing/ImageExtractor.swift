// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns any image ImageIO reads (HEIC, RAW, WebP, TIFF, GIF and the rest) into a JPEG or PNG in the scratch folder,
/// which mtmd's decoder (stb_image) reads. `LlamaEmbedder` then resizes it for its token budget (`ImageSizing`).
nonisolated enum ImageExtractor {
    /// The copy for the model, and what the index keeps about the original.
    struct Prepared: Sendable {
        let path: String
        /// The original's pixels.
        let width: Int
        let height: Int
        /// EXIF DateTimeOriginal, as written by the camera.
        let taken: String?
    }

    /// Writes a downscaled copy for the model. ImageIO decodes straight to the thumbnail size, so a 48 MP photo never
    /// gets decoded at full resolution. Orientation is applied, so the model sees the picture upright.
    ///
    /// - Throws: `ExtractError.tooSmall` when the longer side is under `minSide`, `unreadable` otherwise.
    static func prepare(_ url: URL, maxPixel: Int, minSide: Int, to folder: URL, png: Bool) throws -> Prepared {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ExtractError.unreadable("not an image") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard max(width, height) >= minSide else { throw ExtractError.tooSmall(width, height) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ExtractError.unreadable("can't decode image") }
        let out = folder.appendingPathComponent(UUID().uuidString + (png ? ".png" : ".jpg"))
        try write(thumbnail, to: out, png: png)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return Prepared(path: out.path, width: width, height: height,
                        taken: exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
    }

    /// The image at full resolution (for OCR, where small UI text matters).
    static func fullImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Encodes `image` as PNG (screenshots and pages: sharp text) or JPEG at 0.9 (photos).
    static func write(_ image: CGImage, to url: URL, png: Bool) throws {
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)
        else { throw ExtractError.unreadable("can't write \(url.lastPathComponent)") }
        let properties = png ? nil : [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw ExtractError.unreadable("can't encode image") }
    }
}
