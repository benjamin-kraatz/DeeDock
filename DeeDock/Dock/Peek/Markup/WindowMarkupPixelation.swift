import CoreGraphics

/// Builds the coarse copy of a picture that redactions reveal.
///
/// The whole picture is pixelated once and clipped per redaction, so adding a tenth redaction costs
/// nothing and every redaction shares one block grid. Downscale with smoothing, upscale without it.
nonisolated enum WindowMarkupPixelation {
    static func pixelated(_ image: CGImage, block: Int) -> CGImage? {
        let block = max(2, block)
        let smallSize = (width: max(1, image.width / block), height: max(1, image.height / block))
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let small = CGContext(data: nil, width: smallSize.width, height: smallSize.height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallSize.width, height: smallSize.height))
        guard let reduced = small.makeImage(),
              let large = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        large.interpolationQuality = .none
        large.draw(reduced, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return large.makeImage()
    }
}
