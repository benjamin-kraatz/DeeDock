// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// What a query's text says: its content words, the keyword patterns for them, whether it's a lookup, and which kinds
/// of file it names.
nonisolated extension Searcher {
    /// Codes and IDs ("K7Q2LM", "TRX50") and long numbers ("4815162342": an order, a phone number) mean nothing to an
    /// embedding but everything to keyword search: a query made of them weighs words double and meaning half. Numbers
    /// count since 2026-10-09, when text of digits lost its vectors (`SearchText.hasWords`): a number in a data dump
    /// fell below unrelated meaning matches.
    static func isLookup(_ terms: [String]) -> Bool {
        !terms.isEmpty && terms.allSatisfy {
            $0.contains(where: \.isNumber) && ($0.contains(where: \.isLetter) || $0.count >= 4)
        }
    }

    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "in", "on", "at", "to", "for", "with", "and", "or", "my", "me", "that", "this",
        "these", "those", "from", "about", "where", "what", "which", "who", "when", "is", "was", "are", "were", "be",
        "it", "its", "some", "any", "find", "show", "file", "files", "photo", "photos", "picture", "image", "images",
        "screenshot", "screenshots", "video", "videos", "pdf", "document", "documents", "recording",
        // German, as `terms` sees them (lowercased; ß and umlauts kept)
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "und", "oder", "von", "vom",
        "mit", "im", "auf", "für", "über", "aus", "zum", "zur", "bei", "nach", "am", "mein", "meine", "meinem",
        "meiner", "wo", "wie", "welche", "welcher", "ist", "war", "sind", "zu", "datei", "dateien",
        "dokument", "dokumente", "foto", "fotos", "bild", "bilder", "bildschirmfoto", "bildschirmfotos", "aufnahme",
        // Bengali and Arabic (normalized, as `terms` sees them)
        "এবং", "ও", "এই", "সেই", "একটি", "আমার", "থেকে", "জন্য", "সাথে", "মধ্যে", "কোথায়", "কোন", "কী", "কি", "যে",
        "ছবি", "স্ক্রিনশট", "ভিডিও", "ফাইল", "পিডিএফ",
        "في", "من", "على", "الى", "عن", "مع", "هذا", "هذه", "ذلك", "التي", "الذي", "اين", "ما",
        "صورة", "صور", "لقطة", "شاشة", "فيديو", "ملف", "مستند",
    ]

    /// The content words of a query, normalized as keyword search keeps its text (`SearchText`). Kind words
    /// ("screenshot", "video") and stopwords are dropped: they describe what to look for, not what's in it. Words of
    /// two letters or more count; a Bengali letter with its vowel sign ("মা") is two.
    static func terms(_ text: String) -> [String] {
        var seen = Set<String>()
        return SearchText.normalized(text).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.unicodeScalars.count >= 2 && !stopwords.contains($0) && seen.insert($0).inserted }
    }

    /// FTS5 patterns for the query's words: quoted, and as prefixes for the last word while it's being typed and for
    /// words of languages that attach endings (`SearchText.inflects`).
    static func patterns(_ terms: [String], prefixLast: Bool) -> [String] {
        terms.enumerated().map { index, term in
            let prefix = (prefixLast && index == terms.count - 1) || SearchText.inflects(term)
            return "\"\(term)\"" + (prefix ? "*" : "")
        }
    }

    /// One thing keyword search looks for: a word, or a code ("RE-24-0815", "89.230", "MW-2024-0047") as the phrase
    /// of its parts. FTS5 splits a code into its parts when it indexes text, so as separate words "RE-24-0815" matched
    /// every file with "re", "26" or "2853" in it, and the invoice named after it ranked eighth (DEE-166).
    struct QueryUnit: Hashable {
        /// The word, or the code's parts in order, normalized as `terms` normalizes them.
        let words: [String]

        var isCode: Bool { words.count > 1 }

        /// The FTS5 pattern: a quoted word or phrase, a prefix when `prefix` is set. A word with German spelling
        /// variants (`spellings`) becomes an OR group of them.
        func pattern(prefix: Bool) -> String {
            let quoted = (isCode ? [words.joined(separator: " ")] : Searcher.spellings(of: words[0]))
                .map { "\"" + $0 + "\"" + (prefix ? "*" : "") }
            return quoted.count == 1 ? quoted[0] : "(" + quoted.joined(separator: " OR ") + ")"
        }
    }

    /// A word as it may be spelled in German: ss and ß for each other, and ae, oe, ue for ä, ö, ü and back. People
    /// type "Grossmann" for "Großmann" and "Muenchen" for "München"; keyword search folds accents (ä matches a) but not
    /// these, so a name typed with ss missed the invoices spelled with ß (DEE-166). The word itself comes first.
    static func spellings(of word: String) -> [String] {
        func replacing(_ text: String, _ pairs: [(String, String)]) -> String {
            pairs.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        }
        let toUmlauts = [("ae", "ä"), ("oe", "ö"), ("ue", "ü")], fromUmlauts = [("ä", "ae"), ("ö", "oe"), ("ü", "ue")]
        var forms = [word]
        for form in [replacing(word, [("ss", "ß")]), replacing(word, [("ß", "ss")]), replacing(word, toUmlauts),
                     replacing(word, fromUmlauts)] {
            forms.append(form)
            forms.append(replacing(form, [("ss", "ß")]))
        }
        var seen = Set<String>()
        return forms.filter { seen.insert($0).inserted }
    }

    /// The query's units: its content words (`terms`) and its codes. A code is a run of letters and digits joined by
    /// `-`, `_`, `/`, `.` or `,` with at least one digit in it ("42,00"); its parts stay together whatever their length.
    static func units(_ text: String) -> [QueryUnit] {
        let normalized = SearchText.normalized(text).lowercased()
        var seen = Set<[String]>()
        var units: [QueryUnit] = []
        for chunk in normalized.split(whereSeparator: \.isWhitespace) {
            let parts = chunk.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            let joined = chunk.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            let isCode = parts.count > 1 && joined.contains(where: \.isNumber)
                && joined.allSatisfy { $0.isLetter || $0.isNumber || "-_/.,".contains($0) }
            let candidates = isCode ? [parts] : terms(String(chunk)).map { [$0] }
            for words in candidates where seen.insert(words).inserted {
                units.append(QueryUnit(words: words))
            }
        }
        return units
    }

    /// Whether a query of `units` is a lookup (`isLookup(_:)` for words); a code always is one.
    static func isLookup(units: [QueryUnit]) -> Bool {
        !units.isEmpty && units.allSatisfy { $0.isCode || isLookup($0.words) }
    }

    /// FTS5 patterns for `units`, the last as a prefix while it's being typed, and words of languages that attach
    /// endings always (`patterns(_:prefixLast:)`).
    static func patterns(_ units: [QueryUnit], prefixLast: Bool) -> [String] {
        units.enumerated().map { index, unit in
            unit.pattern(prefix: (prefixLast && index == units.count - 1) || (!unit.isCode && SearchText.inflects(unit.words[0])))
        }
    }

    /// The query's words as an FTS5 OR-query.
    static func ftsQuery(_ text: String, prefixLast: Bool = false) -> String? {
        let words = terms(text)
        guard !words.isEmpty else { return nil }
        return patterns(words, prefixLast: prefixLast).joined(separator: " OR ")
    }

    /// Words that name a kind of file. DigUp's audio and video words are left out: Lookout doesn't index either.
    static let kindWords: [String: FileKind] = [
        "screenshot": .screenshot, "screenshots": .screenshot, "photo": .image, "photos": .image, "picture": .image,
        "pictures": .image, "image": .image, "images": .image, "pdf": .pdf, "pdfs": .pdf, "paper": .pdf,
        "papers": .pdf, "document": .doc, "documents": .doc, "note": .doc, "notes": .doc,
        "bildschirmfoto": .screenshot, "bildschirmfotos": .screenshot, "foto": .image, "fotos": .image,
        "bild": .image, "bilder": .image, "dokument": .doc, "dokumente": .doc, "notiz": .doc, "notizen": .doc,
        "স্ক্রিনশট": .screenshot, "ছবি": .image, "পিডিএফ": .pdf, "নোট": .doc,
        "لقطة": .screenshot, "صورة": .image, "صور": .image, "مستند": .doc, "ملاحظات": .doc,
    ]

    /// Kinds the query asks for ("screenshot of…", "ছবিতে"): a soft boost, not a filter. Bengali attaches case
    /// endings, so a Bengali kind word also counts at the start of a longer word.
    static func kindHints(_ text: String) -> Set<FileKind> {
        Set(SearchText.normalized(text).lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap { word in
                kindWords[word] ?? kindWords.first { key, _ in
                    SearchText.inflects(key) && key.unicodeScalars.count >= 3 && word.hasPrefix(key)
                }?.value
            })
    }
}
