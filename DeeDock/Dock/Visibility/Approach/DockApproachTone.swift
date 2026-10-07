import AppKit
import ImageIO
import SwiftUI

/// The resolved color of the approach glow and whether it reads as a shadow.
///
/// A light glow disappears on a bright wallpaper and a shadow disappears on a dark one, so the
/// automatic tone flips between the two from the wallpaper's luminance near the dock edge.
struct DockApproachTone: Equatable {
    var color: Color
    /// Shadows use lower peak opacities: black at glow strength reads as a hard bar.
    var isShadow: Bool

    static let light = DockApproachTone(color: .white, isShadow: false)
    static let shadow = DockApproachTone(color: .black, isShadow: true)
    static var accent: DockApproachTone { DockApproachTone(color: Color(nsColor: .controlAccentColor), isShadow: false) }

    /// Tone for a wallpaper strip of the given relative luminance, or the appearance's guess without one.
    static func automatic(luminance: Double?, darkAppearance: Bool) -> DockApproachTone {
        guard let luminance else { return darkAppearance ? .light : .shadow }
        return luminance < 0.5 ? .light : .shadow
    }
}

/// Reads the wallpaper luminance next to one screen edge from a bounded thumbnail.
enum DockApproachWallpaperSampler {
    /// Average relative luminance (0...1) of the wallpaper strip nearest `edge`, or nil if the image
    /// cannot be read. Decoding runs off the main actor.
    ///
    /// The strip is measured on the image as stored, so a centered or tiled wallpaper is an
    /// approximation. That is enough to choose between a glow and a shadow.
    static func luminance(of url: URL, near edge: DockEdge) async -> Double? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 64,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return stripLuminance(image, edge: edge)
        }.value
    }

    nonisolated static func stripLuminance(_ image: CGImage, edge: DockEdge) -> Double? {
        let side = 32, strip = 6
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
        var total = 0.0, count = 0.0
        for y in 0..<side {
            for x in 0..<side {
                // Row 0 of the bitmap is the top of the image.
                let near = switch edge {
                case .bottom: y >= side - strip
                case .top: y < strip
                case .left: x < strip
                case .right: x >= side - strip
                }
                guard near else { continue }
                let i = (y * side + x) * 4
                let alpha = Double(bytes[i + 3]) / 255
                guard alpha > 0.2 else { continue }
                let r = Double(bytes[i]) / 255 / alpha, g = Double(bytes[i + 1]) / 255 / alpha, b = Double(bytes[i + 2]) / 255 / alpha
                total += 0.2126 * min(1, r) + 0.7152 * min(1, g) + 0.0722 * min(1, b)
                count += 1
            }
        }
        return count > 0 ? total / count : nil
    }
}
