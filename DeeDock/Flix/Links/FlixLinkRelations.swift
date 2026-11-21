import Foundation

/// Which Flix files were dropped on which pages, for a link row's "↑ You sent 2 files here".
///
/// Stored in `links.json` next to the history: page addresses (already cleaned) mapped to item
/// identifiers, nothing else. "Source of …" needs no storage: it is every item whose download page
/// is the link's address.
nonisolated struct FlixLinkRelationsDocument: Codable, Sendable {
    /// Item identifiers sent to each page, by page address.
    var sent: [String: [UUID]] = [:]

    static let pageLimit = 2_000
    static let itemsPerPage = 50

    /// Records that `items` were dropped on `page`.
    mutating func record(sent items: [UUID], to page: URL) {
        var ids = sent[page.absoluteString] ?? []
        for id in items where !ids.contains(id) { ids.append(id) }
        sent[page.absoluteString] = Array(ids.suffix(Self.itemsPerPage))
        if sent.count > Self.pageLimit, let first = sent.keys.first(where: { $0 != page.absoluteString }) {
            sent[first] = nil
        }
    }
}

/// The relation line a link row shows, from what ``FlixLinkTracker`` indexed.
@MainActor
enum FlixLinkRelationLine {
    /// "Source of “Invoice.pdf”" or "Source of 3 files", then "↑ You sent 2 files here", joined by " · ".
    /// - Parameters:
    ///   - sources: Names of the files downloaded from the page.
    ///   - sentCount: Flix items dropped on the page that are still in the history.
    static func line(sources: [String], sentCount: Int) -> String? {
        var parts: [String] = []
        if sources.count == 1 {
            parts.append(String(localized: .flixLinkSourceOf(String(localized: .flixLabelQuoted(sources[0])))))
        } else if sources.count > 1 {
            parts.append(String(localized: .flixLinkSourceOfMany(sources.count)))
        }
        if sentCount > 0 { parts.append(String(localized: .flixLinkSent(sentCount))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
