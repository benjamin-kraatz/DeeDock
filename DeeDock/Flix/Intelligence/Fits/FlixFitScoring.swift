import Foundation
import UniformTypeIdentifiers

/// Scores how well one history item answers one thing a window asks for.
///
/// ``FlixKeywordFitScorer`` matches words. ``FlixBlendedFitScorer`` adds meaning from Lookout's
/// vectors on top of it when Lookout runs; ``FlixFitRanker`` does not care which one it gets.
nonisolated protocol FlixFitScoring: Sendable {
    /// 0 means unrelated, 1 a certain match. The ranker keeps scores of at least
    /// ``FlixFitRanker/minimumScore``.
    func score(_ wanted: FlixWindowDemand.Wanted, item: FlixFitCandidate, now: Date) -> Double
}

/// What a scorer may know about an item: its name, kind, dates, and phase B's caption. Never the
/// file's contents.
nonisolated struct FlixFitCandidate: Sendable {
    var item: FlixItem
    var caption: String?
    var facts: [String] = []
}

/// Keyword scores raised by Lookout's sense of meaning, for "Fits this window" while Lookout runs.
///
/// `FlixFitsProvider` embeds each wanted phrase once (`FlixSemanticIndex.embed(_:)`), compares it
/// with the candidates' text-averaged file vectors, and keeps only the files that stand out
/// (`FlixSemanticScoring.ranked`, with ``floor`` and ``minimumZ``). Those similarities, mapped to 0…1
/// between ``floor`` and ``strong``, are blended with the keyword score as
/// `max(keyword, 0.6 × meaning + 0.4 × keyword)`: a file that matches by words keeps its score, and
/// one that matches only by meaning passes the ranker's 0.5 bar only when its similarity is near
/// ``strong``. Picture vectors are left out: text-to-picture similarities run on another scale. The
/// numbers are first guesses, like those in `FlixSemanticScoring`; `docs/FLIX.md` lists the checks.
nonisolated struct FlixBlendedFitScorer: FlixFitScoring {
    /// Below this cosine a phrase and a file are unrelated.
    static let floor: Float = 0.30
    /// At this cosine the meaning alone is a match.
    static let strong: Float = 0.55
    /// Standard deviations above the candidates' mean a file must stand.
    static let minimumZ: Float = 1.0
    static let meaningWeight = 0.6

    let keyword: any FlixFitScoring
    /// Meaning scores (0…1) by wanted phrase, then item. Items missing scored nothing by meaning.
    let meaning: [String: [FlixItem.ID: Double]]

    func score(_ wanted: FlixWindowDemand.Wanted, item: FlixFitCandidate, now: Date) -> Double {
        let words = keyword.score(wanted, item: item, now: now)
        guard let meaning = meaning[wanted.phrase]?[item.item.id] else { return words }
        return min(1, max(words, Self.meaningWeight * meaning + (1 - Self.meaningWeight) * words))
    }

    /// A cosine similarity as a 0…1 meaning score.
    static func normalized(_ cosine: Float) -> Double {
        Double(min(1, max(0, (cosine - floor) / (strong - floor))))
    }
}

/// Name, caption, folder, and source overlap with the window's words.
///
/// Every keyword of the wanted phrase that appears in the item's words (or a known synonym, in
/// English and German) adds its weight; words that only describe the file kind ("screenshot",
/// "photo") match the item's kind; time words ("today", "this month") match its date. A match on
/// the kind alone never counts, so "the moodboard" cannot be answered by any picture. Long words
/// also match as the start or end of a longer one, so "Vertrag" finds "Mietvertrag.pdf" (German
/// compounds) and "invoice" finds "invoices2026".
nonisolated struct FlixKeywordFitScorer: FlixFitScoring {
    /// Words that describe what kind of item is wanted, with the kinds that satisfy them.
    static let kindWords: [String: Set<FlixItemKind>] = [
        "screenshot": [.screenshot], "screenshots": [.screenshot], "bildschirmfoto": [.screenshot],
        "photo": [.image, .screenshot], "photos": [.image], "picture": [.image, .screenshot], "image": [.image, .screenshot],
        "bild": [.image, .screenshot], "foto": [.image], "folder": [.folder], "ordner": [.folder],
        "pdf": [.document], "doc": [.document], "spreadsheet": [.document], "deck": [.document], "slides": [.document],
    ]

    /// Words with the same meaning, so "agreement" finds "Contract.pdf" and "Rechnung" finds "invoice".
    static let synonyms: [[String]] = [
        ["contract", "agreement", "vertrag", "nda"], ["invoice", "bill", "rechnung", "receipt", "quittung", "beleg"],
        ["quote", "quotation", "angebot", "estimate", "offer"], ["cv", "resume", "lebenslauf"],
        ["passport", "pass", "reisepass", "id", "ausweis", "personalausweis"], ["signed", "signature", "unterschrieben", "unterschrift"],
        ["photo", "picture", "image", "bild", "foto"], ["screenshot", "bildschirmfoto", "screen"],
        ["moodboard", "mood", "inspiration"], ["spec", "specification", "spezifikation", "requirements"],
        ["report", "bericht"], ["presentation", "deck", "slides", "präsentation"], ["logo", "brand", "marke"],
        ["statement", "kontoauszug"], ["payslip", "lohnabrechnung", "gehaltsabrechnung", "salary"],
        ["error", "fehler", "crash", "bug"], ["draft", "entwurf"], ["photo", "headshot", "portrait"],
    ]

    static let timeWords: Set<String> = ["today", "yesterday", "week", "month", "latest", "newest", "recent",
                                         "heute", "gestern", "woche", "monat", "neueste", "aktuelle"]

    func score(_ wanted: FlixWindowDemand.Wanted, item candidate: FlixFitCandidate, now: Date) -> Double {
        let item = candidate.item
        let haystack = Self.words(of: candidate)
        var matched = 0.0
        var total = 0.0
        var contentMatches = 0
        for keyword in wanted.keywords {
            if Self.timeWords.contains(keyword) {
                total += 0.5
                if Self.matchesTime(keyword, date: item.date, now: now) { matched += 0.5 }
                continue
            }
            if let kinds = Self.kindWords[keyword] {
                total += 0.6
                if kinds.contains(item.kind) || haystack.contains(keyword) { matched += 0.6 }
                continue
            }
            total += 1
            if Self.variants(of: keyword).contains(where: { variant in
                haystack.contains(variant) || (variant.count > 4 && haystack.contains { word in
                    word.count > variant.count && (word.hasPrefix(variant) || word.hasSuffix(variant))
                })
            }) {
                matched += 1
                contentMatches += 1
            }
        }
        guard total > 0 else { return 0 }
        // Kind and time words alone describe half the history; a real match needs a content word,
        // unless the phrase has nothing but kind words ("that screenshot").
        let onlyDescriptive = wanted.keywords.allSatisfy { Self.kindWords[$0] != nil || Self.timeWords.contains($0) }
        guard contentMatches > 0 || (onlyDescriptive && matched > 0) else { return 0 }
        var score = matched / total
        if onlyDescriptive { score *= 0.7 }
        // A little recency, so of two equal matches the newer one wins.
        let days = max(0, now.timeIntervalSince(item.date) / 86_400)
        score += 0.08 * exp(-days / 7)
        return min(1, score)
    }

    /// The words an item offers: name split on separators and case changes, caption, facts, folder,
    /// and the host it was downloaded from.
    static func words(of candidate: FlixFitCandidate) -> Set<String> {
        let item = candidate.item
        var text = splitCamelCase((item.name as NSString).deletingPathExtension)
        if let caption = candidate.caption { text += " " + caption }
        text += " " + candidate.facts.joined(separator: " ")
        if let folder = item.folderName { text += " " + folder }
        if let host = item.sourceHost ?? item.link?.host { text += " " + host.replacingOccurrences(of: ".", with: " ") }
        if let title = item.link?.title { text += " " + title }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Set(FlixDemandFallbackParser.words(in: folded).map(stem))
    }

    static func variants(of keyword: String) -> Set<String> {
        let folded = stem(keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        var result: Set<String> = [folded]
        for group in synonyms where group.contains(where: { stem($0) == folded }) {
            result.formUnion(group.map { stem($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) })
        }
        return result
    }

    /// A crude plural fold: "contracts" → "contract", "invoices" → "invoice".
    static func stem(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    static func splitCamelCase(_ name: String) -> String {
        var result = ""
        var previous: Character?
        for character in name {
            if let previous, character.isUppercase, previous.isLowercase { result.append(" ") }
            result.append(character)
            previous = character
        }
        return result
    }

    static func matchesTime(_ word: String, date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        switch word {
        case "today", "heute": return calendar.isDate(date, inSameDayAs: now)
        case "yesterday", "gestern":
            return calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        case "week", "woche": return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case "month", "monat": return calendar.isDate(date, equalTo: now, toGranularity: .month)
        default: return now.timeIntervalSince(date) < 3 * 86_400
        }
    }
}
