import Foundation

/// Suggests where a download belongs ("✦ Move to Oak & Ash"), among the folders the person already
/// files things in.
///
/// Candidates are the folders of history items outside Downloads, the Desktop, and the home
/// folder, with at least two items each, so only real filing places are offered and no folder is
/// read to find them. With Lookout, a download goes to the folder whose items' vectors it is
/// closest to on average (`FlixSemanticScoring.folderFit`, with a margin over the runner-up). Without
/// Lookout, or when nothing is close enough, rules decide: every distinctive word of a folder's
/// name in the file's name or caption ("Oak & Ash"), then finance words for a finance folder, then
/// pictures for a pictures folder.
nonisolated enum FlixFolderSuggester {
    struct Candidate: Equatable, Sendable {
        var path: String
        var words: Set<String>
        var textCentroid: [Float]?
        var pictureCentroid: [Float]?
    }

    struct Subject: Sendable {
        var name: String
        var caption: String?
        var kind: FlixItemKind
        var vector: LookoutFileVector?
    }

    private static let financeFolders: Set<String> = ["finance", "finanzen", "invoice", "rechnung", "receipt",
                                                      "quittung", "beleg", "tax", "steuer", "bill", "accounting",
                                                      "buchhaltung"]
    private static let financeWords: Set<String> = ["invoice", "rechnung", "receipt", "quittung", "beleg", "bill",
                                                    "tax", "steuer", "statement", "kontoauszug", "payment", "zahlung"]
    private static let pictureFolders: Set<String> = ["picture", "bilder", "photo", "foto", "image", "screenshot",
                                                      "bildschirmfoto"]

    /// The filing folders among `items` (path and optional vector), each with at least
    /// `minimumItems` items. `excluded` are folders that are never suggested (Downloads, Desktop,
    /// home).
    static func candidates(_ items: [(path: String, vector: LookoutFileVector?)], excluded: Set<String>,
                           minimumItems: Int = 2) -> [Candidate] {
        var byFolder: [String: [LookoutFileVector?]] = [:]
        for item in items {
            let folder = (item.path as NSString).deletingLastPathComponent
            // Excluded folders never count, and neither does anything inside Downloads.
            let insideDownloads = excluded.contains { $0.hasSuffix("/Downloads") && folder.hasPrefix($0 + "/") }
            guard !folder.isEmpty, !excluded.contains(folder), !insideDownloads else { continue }
            byFolder[folder, default: []].append(item.vector)
        }
        return byFolder.compactMap { folder, vectors in
            guard vectors.count >= minimumItems else { return nil }
            let present = vectors.compactMap { $0 }
            return Candidate(path: folder,
                             words: FlixWords.distinctive((folder as NSString).lastPathComponent),
                             textCentroid: FlixSemanticScoring.centroid(present.filter { !$0.isPicture }.map(\.vector)),
                             pictureCentroid: FlixSemanticScoring.centroid(present.filter(\.isPicture).map(\.vector)))
        }.sorted { $0.path < $1.path }
    }

    /// The folder `subject` belongs in, or nil.
    static func suggestion(for subject: Subject, among candidates: [Candidate]) -> String? {
        if let vector = subject.vector {
            let scored = candidates.compactMap { candidate -> (String, Float)? in
                guard let centroid = vector.isPicture ? candidate.pictureCentroid : candidate.textCentroid else { return nil }
                return (candidate.path, FlixSemanticScoring.cosine(vector.vector, centroid))
            }.sorted { $0.1 > $1.1 }
            if let best = scored.first, best.1 >= FlixSemanticScoring.folderFit,
               scored.count < 2 || best.1 - scored[1].1 >= FlixSemanticScoring.folderMargin {
                return best.0
            }
        }
        let words = FlixWords.distinctive(subject.name).union(subject.caption.map(FlixWords.distinctive) ?? [])
        let named = candidates.filter { !$0.words.isEmpty && $0.words.isSubset(of: words) }
            .max { $0.words.count < $1.words.count || ($0.words.count == $1.words.count && $0.path.count < $1.path.count) }
        if let named { return named.path }
        if !words.isDisjoint(with: financeWords),
           let finance = candidates.first(where: { !$0.words.isDisjoint(with: financeFolders) }) {
            return finance.path
        }
        if subject.kind == .image || subject.kind == .screenshot,
           let pictures = candidates.first(where: { !$0.words.isDisjoint(with: pictureFolders) }) {
            return pictures.path
        }
        return nil
    }
}
