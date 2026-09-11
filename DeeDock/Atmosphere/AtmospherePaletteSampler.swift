import AppKit
import ImageIO

/// Samples bounded thumbnails, never full-size wallpaper pixels on the rendering path.
enum AtmospherePaletteSampler {
    static func wallpaper(_ url: URL, mode: AtmosphereWallpaperMode) async -> AtmospherePalette? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 64,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return sample(image, mode: mode)
        }.value
    }

    static func icon(_ image: NSImage?) -> AtmospherePalette? {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return sample(cg, mode: .gradient)
    }

    nonisolated private static func sample(_ image: CGImage, mode: AtmosphereWallpaperMode) -> AtmospherePalette? {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var bins: [Int: (count: Double, r: Double, g: Double, b: Double)] = [:]
        var sums = (r: 0.0, g: 0.0, b: 0.0, count: 0.0)
        var left = sums, right = sums
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                let alpha = Double(bytes[i + 3]) / 255
                guard alpha > 0.2 else { continue }
                let r = min(1, Double(bytes[i]) / 255 / alpha)
                let g = min(1, Double(bytes[i + 1]) / 255 / alpha)
                let b = min(1, Double(bytes[i + 2]) / 255 / alpha)
                sums.r += r; sums.g += g; sums.b += b; sums.count += 1
                let key = Int(r * 7) * 64 + Int(g * 7) * 8 + Int(b * 7)
                var bin = bins[key] ?? (0, 0, 0, 0)
                bin.count += 1; bin.r += r; bin.g += g; bin.b += b; bins[key] = bin
                if (y < 6 || y >= side - 6) && x < 6 {
                    left.r += r; left.g += g; left.b += b; left.count += 1
                }
                if (y < 6 || y >= side - 6) && x >= side - 6 {
                    right.r += r; right.g += g; right.b += b; right.count += 1
                }
            }
        }
        guard sums.count > 0 else { return nil }
        let average = AtmosphereColor(sums.r / sums.count, sums.g / sums.count, sums.b / sums.count)
        if mode == .average { return .init(first: average, second: average) }
        if mode == .corners, left.count > 0, right.count > 0 {
            return .init(first: .init(left.r / left.count, left.g / left.count, left.b / left.count),
                         second: .init(right.r / right.count, right.g / right.count, right.b / right.count))
        }
        let prominent = bins.sorted { $0.key < $1.key }.max { $0.value.count < $1.value.count }!.value
        return .init(first: .init(prominent.r / prominent.count, prominent.g / prominent.count, prominent.b / prominent.count), second: average)
    }
}
