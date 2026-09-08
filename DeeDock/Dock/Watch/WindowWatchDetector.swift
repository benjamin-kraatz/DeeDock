import CoreGraphics
import Foundation

/// Unit coordinates measured from the preview's top-left, independent of screen origin and scale.
nonisolated struct WindowWatchRegion: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    /// The values displayed to the user and used by the crop must describe the same bounded rectangle.
    var clamped: Self {
        let rect = rect
        return Self(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var rect: CGRect {
        CGRect(x: min(max(x, 0), 0.95), y: min(max(y, 0), 0.95),
               width: min(max(width, 0.05), 1 - min(max(x, 0), 0.95)),
               height: min(max(height, 0.05), 1 - min(max(y, 0), 0.95)))
    }
}

/// One-shot evidence rules. Pixel stability is never interpreted as task completion.
nonisolated struct WindowWatchDetector: Sendable {
    private var baseline: [UInt8]?
    private var previous: [UInt8]?
    private var confirmations = 0
    private var sawPhraseAbsent = false

    mutating func consume(pixels: [UInt8], lines: [String], phrase: String) -> Bool {
        if !phrase.isEmpty {
            let found = lines.contains { $0.compare(phrase, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if !found { sawPhraseAbsent = true }
            confirmations = found && sawPhraseAbsent ? confirmations + 1 : 0
        } else {
            guard let baseline, let previous else {
                baseline = pixels
                previous = pixels
                return false
            }
            // Reject single-frame noise and moving imagery. A changed image must settle for three samples.
            confirmations = Self.changedFraction(baseline, pixels) >= 0.005
                && Self.changedFraction(previous, pixels) < 0.002 ? confirmations + 1 : 0
            self.previous = pixels
        }
        return confirmations >= 3
    }

    /// RGBA samples use the largest RGB channel difference and ignore alpha. Counting affected
    /// pixels keeps a localized label change from being diluted by the unchanged background.
    private static func changedFraction(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty, a.count.isMultiple(of: 4) else { return 1 }
        var changed = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            let difference = max(abs(Int(a[index]) - Int(b[index])),
                                 abs(Int(a[index + 1]) - Int(b[index + 1])),
                                 abs(Int(a[index + 2]) - Int(b[index + 2])))
            // Ignore small rasterization fluctuations without discarding equal-luminance colors.
            if difference >= 24 { changed += 1 }
        }
        return Double(changed) / Double(a.count / 4)
    }
}
