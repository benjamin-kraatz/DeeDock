import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns the frame a portal is showing into a PNG the user can keep.
///
/// Only what is visible is written: the retained frame reduced to the current crop and zoom, so a
/// saved file matches the portal instead of the whole source window. Nothing is written anywhere
/// the user did not name; the save panel picks the destination.
nonisolated enum WindowPortalExport {
    /// The pixels the portal is showing.
    ///
    /// `viewport` is in the same top-left unit coordinates the presentation uses, and `cropping(to:)`
    /// measures from the top-left of the image data, so no vertical flip belongs here. The rectangle
    /// is rounded outwards and clamped to the frame, which keeps a one-pixel selection valid.
    static func visibleFrame(of image: CGImage, viewport: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixels = CGRect(x: viewport.minX * Double(image.width),
                            y: viewport.minY * Double(image.height),
                            width: viewport.width * Double(image.width),
                            height: viewport.height * Double(image.height)).integral
        let bounded = pixels.intersection(bounds)
        guard !bounded.isNull, bounded.width >= 1, bounded.height >= 1 else { return nil }
        return bounded == bounds ? image : image.cropping(to: bounded)
    }

    /// PNG data for `image`, or `nil` when the destination cannot be finalized.
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A file name that names the window and the moment, safe to hand to the save panel.
    ///
    /// Path separators and colons are replaced rather than dropped, because window titles routinely
    /// contain both and a silent deletion turns two different titles into one file name.
    static func suggestedFilename(source: String, at date: Date) -> String {
        let stripped = source.unicodeScalars.map { scalar -> Character in
            CharacterSet.newlines.contains(scalar) || scalar == "/" || scalar == ":" ? " " : Character(scalar)
        }
        let collapsed = String(stripped).split(separator: " ").joined(separator: " ")
        let name = collapsed.isEmpty ? "Portal" : String(collapsed.prefix(80))
        return "\(name) \(timestamp.string(from: date)).png"
    }

    /// Fixed field order, no locale: file names sort by time in every region and script.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}
