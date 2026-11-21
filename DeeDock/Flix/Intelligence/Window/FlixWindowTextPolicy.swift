import Foundation

/// When a reader found enough text to stop the chain.
///
/// The threshold is ``minimumWords`` words of three or more letters: about one sentence. A web
/// portal's "Upload documents. Attach the signed contract and this month's invoice." clears it;
/// an empty Chromium window (only its toolbar's "Back", "Reload"), a canvas, or a window of icons
/// does not, so the next reader runs. Toolbar labels count too, which is why the bar is a sentence
/// and not a word or two.
nonisolated enum FlixWindowTextPolicy {
    static let minimumWords = 8

    static func isEnough(_ text: String) -> Bool {
        wordCount(text) >= minimumWords
    }

    static func wordCount(_ text: String) -> Int {
        var count = 0
        for word in text.split(whereSeparator: { !$0.isLetter }) where word.count >= 3 {
            count += 1
            if count >= minimumWords { return count }
        }
        return count
    }
}
