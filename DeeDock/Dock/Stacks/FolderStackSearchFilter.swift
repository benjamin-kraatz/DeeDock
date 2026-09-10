import Foundation

/// Name matching for the folder panel's filter field.
///
/// Terms match independently and in any order, so "pdf report" finds "Report 2024.pdf". Case,
/// diacritics, and width are folded because Finder hands back names in the user's own language.
nonisolated enum FolderStackSearchFilter {
    /// Listings at or below this size stay chrome-free; scanning them by eye is faster than typing.
    static let threshold = 10

    /// Splits a raw query into folded terms. An all-whitespace query yields no terms and matches everything.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { $0.folded }
    }

    /// Matches the display name, and the file extension on its own so "png" finds every image.
    static func matches(_ reference: FolderStackEntryReference, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let name = reference.name.folded
        let pathExtension = reference.url.pathExtension.folded
        return terms.allSatisfy { term in
            name.contains(term) || (!pathExtension.isEmpty && pathExtension.hasPrefix(term))
        }
    }
}

private extension StringProtocol {
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
