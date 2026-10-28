import Foundation

/// The search field's picture and the words searched before it, as the mockup's chip behaves
/// (`docs/mockups/lookout-image-search.html`). Pure, so every path is testable without a view.
///
/// - A picture replaces the words in the field. The words from before the first picture are kept: a later picture
///   (Find Similar on a result of the picture search) replaces the picture and keeps them.
/// - Words typed after the chip search together with the picture (DEE-126); the field holds them, not the session.
/// - ⌫ on the empty field, ✕ on the chip, and "Back to …" remove the picture and give the words back.
/// - The clear button and Escape remove the picture and the words.
struct LookoutPictureSession: Equatable {
    /// The picture searched with, or nil while searching by words.
    private(set) var picture: LookoutPictureQuery?
    /// The words searched before the first picture, trimmed; empty when there were none.
    private(set) var wordsBefore = ""

    var isActive: Bool { picture != nil }

    /// Starts searching with `picture`.
    ///
    /// - Parameter words: What the field held (ignored when a picture is already searched with).
    mutating func begin(_ picture: LookoutPictureQuery, replacingWords words: String) {
        if self.picture == nil { wordsBefore = words.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.picture = picture
    }

    /// Removes the picture.
    ///
    /// - Parameter restoringWords: Give the words from before back (⌫, ✕, "Back to …"), or not (clear, Escape).
    /// - Returns: The text the field shows next.
    mutating func remove(restoringWords: Bool) -> String {
        let words = restoringWords ? wordsBefore : ""
        picture = nil
        wordsBefore = ""
        return words
    }
}
