import Foundation

/// What a plain-words search asks for, before it becomes tokens: the structured half (activity,
/// kind, time, amount, place, site) and the words left over, which are matched by meaning.
nonisolated struct FlixQueryUnderstanding: Equatable, Sendable {
    var activity: FlixActivity?
    var kinds: [FlixItemKind] = []
    /// File name extensions without the dot ("pdf").
    var extensions: [String] = []
    /// At most this many days old.
    var days: Int?
    /// How the time was said, for the token's label.
    var timePhrase: FlixTimePhrase?
    /// A money amount the file's total must be above.
    var minimumAmount: Double?
    var currency: String?
    /// A folder name the path must contain ("Downloads").
    var folder: String?
    /// A site the download came from ("github.com").
    var site: String?
    /// The words left over, matched against names, captions, and by meaning.
    var topic: String?

    var isEmpty: Bool {
        activity == nil && kinds.isEmpty && extensions.isEmpty && days == nil && minimumAmount == nil
            && folder == nil && site == nil && (topic ?? "").isEmpty
    }
}

/// How a time range was said, so its token reads like the sentence ("Today", "Last 7 days").
nonisolated enum FlixTimePhrase: Equatable, Sendable {
    case today, yesterday, week, month
    case days(Int)
}

/// Understands a plain-words search without a model: English and German keywords for activity,
/// kind, time, amount, place, and site; everything else becomes the topic.
///
/// The fallback when Apple Intelligence is unavailable or too slow, and the source of truth for
/// what a token means: the model's answer is mapped onto the same ``FlixQueryUnderstanding``.
nonisolated enum FlixQueryParser {
    private static let stopwords: Set<String> = [
        // English
        "the", "a", "an", "with", "that", "this", "these", "those", "me", "my", "mine", "from", "of", "for", "over",
        "under", "in", "on", "at", "i", "to", "and", "or", "is", "was", "it", "some", "all", "any", "can", "find",
        "show", "where", "what", "which", "file", "files", "thing", "things", "stuff", "about", "last", "this", "week",
        "month", "days", "day", "today", "yesterday", "ago", "past", "recent", "recently", "everything", "more", "than",
        "folder", "site", "sent", "send", "got", "get", "received", "downloaded", "opened", "saved", "edited", "created",
        // German
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "mit", "von", "vom", "aus",
        "fur", "uber", "unter", "im", "in", "am", "an", "auf", "ich", "mir", "mein", "meine", "meinen", "und", "oder",
        "ist", "war", "alle", "alles", "zeig", "zeige", "finde", "wo", "was", "welche", "datei", "dateien", "zum", "zur",
        "letzte", "letzten", "letzter", "diese", "dieser", "diesen", "woche", "monat", "tage", "tagen", "tag", "heute",
        "gestern", "seit", "mehr", "als", "ordner", "geschickt", "gesendet", "heruntergeladen", "runtergeladen",
        "bekommen", "erhalten", "geoffnet", "gespeichert", "bearbeitet", "erstellt", "hat", "habe", "hab",
    ]

    private static let kindWords: [(words: Set<String>, kind: FlixItemKind)] = [
        (["screenshot", "screenshots", "bildschirmfoto", "bildschirmfotos", "screen"], .screenshot),
        (["photo", "photos", "picture", "pictures", "image", "images", "foto", "fotos", "bild", "bilder"], .image),
        (["folder", "folders", "ordner"], .folder),
        (["app", "apps", "application", "applications", "programm", "programme"], .app),
        (["document", "documents", "doc", "docs", "dokument", "dokumente"], .document),
        (["link", "links", "page", "pages", "seite", "seiten", "website", "webseite"], .link),
    ]
    private static let extensionWords: [String: String] = [
        "pdf": "pdf", "pdfs": "pdf", "spreadsheet": "xlsx", "spreadsheets": "xlsx", "tabelle": "xlsx",
        "tabellen": "xlsx", "excel": "xlsx", "keynote": "key", "zip": "zip", "zips": "zip",
    ]

    static func parse(_ text: String) -> FlixQueryUnderstanding {
        var result = FlixQueryUnderstanding()
        var sentence = " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + " "
        let original = text

        // Amounts first: their digits must not reach the topic.
        let amount = #"(?:over|above|more than|greater than|at least|uber|mehr als|ab|mindestens)\s*(€|\$|£|eur|usd|chf)?\s*(\d[\d.,']*)\s*(€|\$|£|eur|euro|usd|dollar|chf)?"#
        if let match = firstMatch(amount, in: sentence) {
            result.minimumAmount = FlixFactExtractor.parseNumber(match.groups[1])
            let symbol = (match.groups[0].isEmpty ? match.groups[2] : match.groups[0]).lowercased()
            result.currency = symbol.isEmpty ? nil : ["$", "usd", "dollar"].contains(symbol) ? "USD"
                : symbol == "£" ? "GBP" : symbol == "chf" ? "CHF" : "EUR"
            sentence = sentence.replacingCharacters(in: match.range, with: " ")
        }

        // Time.
        if let match = firstMatch(#"(?:last|past|letzten|vergangenen)\s+(\d{1,3})\s+(?:days|tagen|tage)"#, in: sentence),
           let days = Int(match.groups[0]) {
            result.days = days
            result.timePhrase = .days(days)
        } else if contains(sentence, ["today", "heute"]) {
            (result.days, result.timePhrase) = (1, .today)
        } else if contains(sentence, ["yesterday", "gestern"]) {
            (result.days, result.timePhrase) = (2, .yesterday)
        } else if contains(sentence, ["last week", "this week", "past week", "letzte woche", "letzten woche",
                                      "diese woche", "dieser woche", "vergangene woche"]) {
            (result.days, result.timePhrase) = (7, .week)
        } else if contains(sentence, ["last month", "this month", "past month", "letzten monat", "diesen monat",
                                      "letzter monat", "vergangenen monat"]) {
            (result.days, result.timePhrase) = (30, .month)
        }

        // Activity.
        if contains(sentence, ["sent", "downloaded", "got", "received", "geschickt", "gesendet", "heruntergeladen",
                               "runtergeladen", "bekommen", "erhalten", "zugeschickt"]) {
            result.activity = .downloaded
        } else if contains(sentence, ["opened", "geoffnet", "angesehen", "looked at"]) {
            result.activity = .opened
        } else if contains(sentence, ["saved", "edited", "changed", "gespeichert", "bearbeitet", "geandert"]) {
            result.activity = .saved
        } else if contains(sentence, ["created", "erstellt", "new files", "neue dateien"]) {
            result.activity = .created
        }

        // Place and site.
        if let match = firstMatch(#"(?:in|im|from|aus)\s+(?:the\s+|dem\s+)?(?:folder|ordner)\s+["“„]?([^"”“,]+?)["”“]?\s*$"#,
                                  in: sentence) ?? firstMatch(#"(?:in|im|from|aus)\s+(?:the\s+|dem\s+)?(?:folder|ordner)\s+["“„]?([^\s"”“,]+)"#,
                                                              in: sentence) {
            result.folder = cased(match.groups[0], in: original)
            sentence = sentence.replacingCharacters(in: match.range, with: " ")
        } else {
            let places: [(Set<String>, String)] = [(["downloads", "download"], "Downloads"),
                                                   (["desktop", "schreibtisch"], "Desktop"),
                                                   (["documents", "dokumente"], "Documents"),
                                                   (["icloud"], "Mobile Documents")]
            for (words, folder) in places {
                if let match = firstMatch(#"(?:in|im|on|auf|from|aus)\s+(?:the\s+|my\s+|dem\s+|meinen\s+|den\s+)?("# +
                                          words.joined(separator: "|") + #")\b"#, in: sentence) {
                    result.folder = folder
                    sentence = sentence.replacingCharacters(in: match.range, with: " ")
                    break
                }
            }
        }
        if let match = firstMatch(#"\b([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|io|de|app|dev|co|ch|at|eu|uk))\b"#, in: sentence) {
            result.site = match.groups[0]
            sentence = sentence.replacingCharacters(in: match.range, with: " ")
        }

        // Kinds and extensions, then the topic from what is left.
        var words = FlixWords.words(sentence)
        for (kindWords, kind) in kindWords where words.contains(where: kindWords.contains) {
            if !result.kinds.contains(kind) { result.kinds.append(kind) }
            words.removeAll(where: kindWords.contains)
        }
        if result.kinds.contains(.screenshot) { result.kinds.removeAll { $0 == .image } }
        for (word, ext) in extensionWords where words.contains(word) {
            if !result.extensions.contains(ext) { result.extensions.append(ext) }
            words.removeAll { $0 == word }
        }
        let folderWords = Set(result.folder.map(FlixWords.words) ?? [])
        let topicWords = words.filter { !stopwords.contains($0) && !folderWords.contains($0) && !($0.allSatisfy(\.isNumber) && $0.count < 3) }
        if !topicWords.isEmpty { result.topic = cased(topicWords.joined(separator: " "), in: original) }
        return result
    }

    // MARK: Helpers

    private static func contains(_ sentence: String, _ phrases: [String]) -> Bool {
        phrases.contains { sentence.contains(" " + $0 + " ") || sentence.contains(" " + $0 + ",") || sentence.contains(" " + $0 + ".") }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let groups = (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        return (range, groups)
    }

    /// The words as the person typed them: "Oak & Ash", not "oak ash". When they stand together in
    /// the original, separated only by spaces, `&`, or dashes, that stretch is returned; otherwise
    /// each word in its typed form, joined by spaces.
    static func cased(_ words: String, in original: String) -> String {
        let parts = FlixWords.words(words)
        guard !parts.isEmpty else { return words.trimmingCharacters(in: .whitespaces) }
        let folded = original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let pattern = "\\b" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "[\\s&+\\-–]+") + "\\b"
        if (folded as NSString).length == (original as NSString).length,
           let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: folded, range: NSRange(location: 0, length: (folded as NSString).length)) {
            return (original as NSString).substring(with: match.range)
        }
        return parts.map { part in
            original.range(of: part, options: [.caseInsensitive, .diacriticInsensitive]).map { String(original[$0]) } ?? part
        }.joined(separator: " ")
    }
}
