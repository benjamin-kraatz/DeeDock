import CoreGraphics
import Foundation
import ImageIO

/// A picture to search with, sized the way the indexer sizes the pictures it stores, as packed RGB pixels: what the
/// query service's image encoder takes (`LookoutQueryServing.embedPicture`).
///
/// The app makes it, because the app holds the access: a dropped file comes with the drag's sandbox extension and a
/// pasted picture lives on the pasteboard, and the service may not be allowed to read either. It's made in memory and
/// sent over XPC; nothing is written to disk on either side.
///
/// The steps follow the indexer's (`Indexer.prepare`, `ImageExtractor.prepare`, `LlamaEmbedder.load`): ImageIO decodes
/// straight to a thumbnail of at most 1536 px for a screenshot and 1024 px for a photo, upright; then the bicubic resize
/// fills the screenshot or photo budget (`ImageSizing`). The indexer passes a JPEG or PNG copy in between, so a query's
/// pixels differ from a stored picture's by that encoding only.
nonisolated struct QueryPicture: Sendable, Equatable {
    /// Why a picture can't be searched with.
    enum Failure: Error, Equatable {
        /// ImageIO can't decode it.
        case unreadable
        /// It's too thin for the encoder (`ImageSizing.targetSize` has no size for it).
        case tooThin
    }

    /// Packed RGB, 3 bytes a pixel, row by row.
    let pixels: Data
    let width: Int
    let height: Int
    /// The soft tokens it was sized for: `screenshotBudget` or `photoBudget` (`IndexOptions`).
    let budget: Int

    /// Sizes a picture for the encoder.
    ///
    /// - Parameters:
    ///   - source: The picture's bytes (a file's, or a pasteboard's PNG or TIFF data).
    ///   - screenshot: Size it as a screenshot (1536 px, 280 tokens) rather than a photo (1024 px, 140 tokens), as the
    ///     indexer would have stored it.
    /// - Throws: `Failure`.
    static func make(from source: CGImageSource, screenshot: Bool, options: IndexOptions = IndexOptions()) throws
        -> QueryPicture {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: screenshot ? 1536 : 1024,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw Failure.unreadable }
        return try make(from: image, budget: screenshot ? options.screenshotBudget : options.photoBudget)
    }

    /// Sizes a decoded image for `budget` soft tokens.
    ///
    /// - Throws: `Failure`.
    static func make(from image: CGImage, budget: Int) throws -> QueryPicture {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { throw Failure.unreadable }
        guard let target = ImageSizing.targetSize(height: height, width: width, budget: budget) else {
            throw Failure.tooThin
        }
        let rgb = try rgbPixels(of: image)
        let sized = rgb.withUnsafeBufferPointer {
            ImageSizing.resizeBicubic($0.baseAddress!, width: width, height: height,
                                      toWidth: target.width, toHeight: target.height)
        }
        return QueryPicture(pixels: Data(sized), width: target.width, height: target.height, budget: budget)
    }

    /// The image's pixels as packed RGB in its own color space when that's RGB (stb_image, which the indexer's path
    /// goes through, keeps the file's values and ignores its profile), else in sRGB. Transparent parts come out over
    /// black, as an unpremultiplied PNG's colors mostly do.
    private static func rgbPixels(of image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw Failure.unreadable }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        rgb.withUnsafeMutableBufferPointer { rgb in
            rgba.withUnsafeBufferPointer { rgba in
                for pixel in 0..<(width * height) {
                    rgb[pixel * 3] = rgba[pixel * 4]
                    rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
                    rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
                }
            }
        }
        return rgb
    }
}
