import Foundation

/// Finds versions of one document by name ("Contract draft v2", "Contract draft v3", "Signed
/// contract") and ranks them, newest highest, for the version pill and the "newer version exists"
/// question.
///
/// A family is two or more items whose names match once version marks are removed (`v3`,
/// `version 2`, `rev 4`, `(2)`, final, signed, draft, copy, and their German words), of the same
/// broad kind, where at least one name carries a mark. Cryptic names (`document (3).pdf`) never
/// form families: their shared word says nothing. When Lookout holds vectors for two members,
/// a member clearly unrelated to the family's newest one leaves it.
///
/// Rank: a signed copy beats a final one, which beats a numbered or plain one, which beats a draft;
/// within a level the higher number, then the later date, wins.
nonisolated enum FlixVersionFamilies {
    struct Member: Sendable {
        var id: FlixItem.ID
        var name: String
        var kind: FlixItemKind
        var date: Date
        var vector: LookoutFileVector?
    }

    struct Placement: Equatable, Sendable {
        var group: String
        /// 0 is the oldest; higher is newer.
        var rank: Int
    }

    /// How a name marks its version. Ordered: a later level is a newer document.
    enum Level: Int, Comparable, Sendable {
        case draft, plain, final, signed
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    struct Mark: Equatable, Sendable {
        var key: String
        var level: Level
        var number: Int?
        /// The name carried any version mark at all.
        var isMarked: Bool
    }

    /// Below this, two members' vectors say they are different documents.
    static let unrelatedBelow: Float = 0.5

    private static let numberPatterns: [NSRegularExpression] = [
        #"\bv\.?\s?(\d{1,3})\b"#, #"\bversion\s?(\d{1,3})\b"#, #"\brev(?:ision)?\.?\s?(\d{1,3})\b"#,
        #"\((\d{1,2})\)\s*$"#, #"\bfassung\s?(\d{1,3})\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    private static let levelWords: [(String, Level)] = [
        ("unterschrieben", .signed), ("signiert", .signed), ("signed", .signed), ("final", .final),
        ("endfassung", .final), ("draft", .draft), ("entwurf", .draft), ("copy", .plain), ("kopie", .plain),
    ]

    /// The family key and version mark of one name, or nil when it can't belong to a family.
    static func mark(for name: String) -> Mark? {
        guard !FlixFileNaming.isCryptic(name) else { return nil }
        var stem = (name as NSString).deletingPathExtension.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                                     locale: nil)
        var number: Int?
        var marked = false
        for pattern in numberPatterns {
            let range = NSRange(stem.startIndex..., in: stem)
            guard let match = pattern.firstMatch(in: stem, range: range),
                  let digits = Range(match.range(at: 1), in: stem), let whole = Range(match.range, in: stem) else { continue }
            number = Int(stem[digits])
            stem.replaceSubrange(whole, with: " ")
            marked = true
        }
        var words = FlixWords.words(stem)
        var found: [Level] = []
        for (word, wordLevel) in levelWords where words.contains(word) {
            words.removeAll { $0 == word }
            marked = true
            found.append(wordLevel)
        }
        // "Copy" marks a version without moving it; "final draft" is final, "draft" alone a draft.
        let level = found.filter { $0 != .plain }.max() ?? .plain
        let key = words.map(FlixWords.stem).joined(separator: " ")
        guard key.count >= 4, words.contains(where: { !FlixWords.generic.contains($0) && !$0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return Mark(key: key, level: level, number: number, isMarked: marked)
    }

    /// Version placements for every item that belongs to a family.
    static func groups(_ members: [Member]) -> [FlixItem.ID: Placement] {
        var families: [String: [(Member, Mark)]] = [:]
        for member in members {
            guard let mark = mark(for: member.name) else { continue }
            let family = mark.key + "|" + kindClass(member.kind)
            families[family, default: []].append((member, mark))
        }
        var placements: [FlixItem.ID: Placement] = [:]
        for (family, entries) in families where entries.count > 1 && entries.contains(where: { $0.1.isMarked }) {
            var sorted = entries.sorted { a, b in
                if a.1.level != b.1.level { return a.1.level < b.1.level }
                if (a.1.number ?? 0) != (b.1.number ?? 0) { return (a.1.number ?? 0) < (b.1.number ?? 0) }
                return a.0.date < b.0.date
            }
            if let newest = sorted.last?.0.vector, let newestID = sorted.last?.0.id {
                sorted.removeAll { entry in
                    guard let vector = entry.0.vector, entry.0.id != newestID,
                          FlixSemanticScoring.isComparable(vector, newest) else { return false }
                    return FlixSemanticScoring.cosine(vector.vector, newest.vector) < unrelatedBelow
                }
            }
            guard sorted.count > 1 else { continue }
            for (rank, entry) in sorted.enumerated() {
                placements[entry.0.id] = Placement(group: "v:" + family, rank: rank)
            }
        }
        return placements
    }

    private static func kindClass(_ kind: FlixItemKind) -> String {
        switch kind {
        case .image, .screenshot: "image"
        case .document, .other: "document"
        case .folder: "folder"
        case .app: "app"
        case .link: "link"
        }
    }
}
