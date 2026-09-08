import CoreGraphics
import Foundation

typealias WindowWatchRegion = NormalizedWindowRegion

/// One-shot evidence rules. Pixel stability is never interpreted as task completion.
nonisolated struct WindowWatchDetector: Sendable {
    private var baseline: [UInt8]?
    private var previous: [UInt8]?
    private var confirmations = 0
    private var sawPhraseAbsent = false
    private(set) var observation: WindowWatchObservation = .baseline
    private var wasChanged = false

    mutating func consume(pixels: [UInt8], lines: [String], phrase: String) -> Bool {
        let changed: Bool
        let settled: Bool
        if let baseline, let previous {
            changed = Self.changedFraction(baseline, pixels) >= 0.005
            settled = Self.changedFraction(previous, pixels) < 0.002
            if changed {
                observation = !wasChanged ? .change : (settled ? .settling : .changing)
            } else if wasChanged {
                observation = .returned
            }
        } else {
            baseline = pixels
            changed = false
            settled = false
            observation = .baseline
        }
        previous = pixels
        wasChanged = changed
        if !phrase.isEmpty {
            let found = lines.contains { $0.compare(phrase, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if !found { sawPhraseAbsent = true }
            confirmations = found && sawPhraseAbsent ? confirmations + 1 : 0
        } else {
            // Reject single-frame noise and moving imagery. A changed image must settle for three samples.
            confirmations = changed && settled ? confirmations + 1 : 0
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
