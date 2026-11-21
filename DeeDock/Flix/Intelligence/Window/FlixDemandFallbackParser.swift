import Foundation
import UniformTypeIdentifiers

/// Reads a window's text into a ``FlixWindowDemand`` with plain rules, for Macs without Apple
/// Intelligence and for the tile's background count (which never uses a model).
///
/// - **Wanted items**: the object of a request verb ("attach", "upload", "send", "include",
///   "provide", "share", "drop", and German "anhängen", "hochladen", "senden", "beifügen"), up to the
///   end of the clause, split on "and", "und", commas, and "&". "Attach the signed contract and this
///   month's invoice." gives "the signed contract" and "this month's invoice". German puts the verb
///   last ("Bitte den Mietvertrag hochladen"), so when nothing follows the verb, the words before it
///   are the object.
/// - **Types**: type words ("PDF", "JPG", "Word", "images") on a line that also carries a limit word
///   ("only", "accepted", "allowed", "supported", "formats", "nur", "erlaubt", "Formate"…).
/// - **Size**: "max 5 MB", "up to 10 MB", "5 MB max", "bis zu 5 MB", "höchstens 2 MB", "≤ 5 MB".
/// - **Page kind**: upload words ("drop files", "choose file", "hochladen") make an upload page; the
///   app's category (mail, chat) is supplied by the caller.
nonisolated enum FlixDemandFallbackParser {
    static let requestVerbs = [
        "attach", "attaching", "upload", "uploading", "send", "sending", "include", "including", "provide",
        "share", "sharing", "drop", "add", "submit", "anhängen", "hochladen", "senden", "schicken",
        "beifügen", "mitschicken", "teilen", "einreichen",
    ]
    static let limitWords = [
        "only", "accepted", "accepts", "allowed", "supported", "formats", "format", "file types", "filetypes",
        "must be", "nur", "erlaubt", "akzeptiert", "unterstützt", "formate", "dateitypen", "dateiformat",
    ]
    static let typeWords: Set<String> = [
        "pdf", "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg", "doc", "docx", "xls", "xlsx",
        "ppt", "pptx", "txt", "csv", "rtf", "zip", "md", "mp4", "mov", "mp3", "word", "excel", "powerpoint",
        "image", "images", "photo", "photos", "picture", "pictures", "bild", "bilder", "foto", "fotos",
    ]
    static let uploadWords = ["drop files", "drag files", "choose file", "choose files", "browse files",
                              "select file", "select files", "upload", "dateien ablegen", "datei auswählen",
                              "dateien auswählen", "hochladen"]
    static let stopWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "your", "my", "our", "his", "her", "their", "its",
        "please", "also", "and", "or", "of", "for", "to", "with", "in", "on", "me", "us", "it", "here", "there",
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "ihr", "ihre",
        "ihren", "dein", "deine", "mein", "meine", "unser", "unsere", "bitte", "und", "oder", "von", "für",
        "mit", "auch", "hier", "mir", "uns", "s", "file", "files", "datei", "dateien", "document", "documents",
        "dokument", "dokumente", "once", "you", "re", "is", "are",
    ]

    /// - Parameter pageKind: The kind the app implies (mail, chat), refined by the text.
    static func parse(_ text: String, pageKind: FlixWindowDemand.PageKind = .other) -> FlixWindowDemand {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var demand = FlixWindowDemand(pageKind: pageKind)
        let lowered = text.lowercased()
        if pageKind == .other, uploadWords.contains(where: lowered.contains) { demand.pageKind = .upload }
        var types: [UTType] = []
        for line in lines {
            let lowerLine = line.lowercased()
            if limitWords.contains(where: lowerLine.contains) || lowerLine.contains("max") {
                for word in words(in: lowerLine) where typeWords.contains(word) {
                    if let type = FlixWindowDemand.type(named: word), !types.contains(type) { types.append(type) }
                }
            }
            if demand.maximumBytes == nil, let bytes = sizeLimit(in: lowerLine) { demand.maximumBytes = bytes }
        }
        demand.acceptedTypes = types
        demand.wanted = wanted(in: lines)
        return demand
    }

    // MARK: Pieces

    /// The first size limit in a line, in bytes.
    static func sizeLimit(in line: String) -> Int64? {
        let number = #"(\d+(?:[.,]\d+)?)\s*(kb|mb|gb)\b"#
        let patterns = [
            #"(?:max(?:imum)?\.?|up to|limit(?:ed to)?|no (?:larger|bigger) than|less than|under|bis zu|höchstens|maximal|max\.|≤|<=|<)\s*(?:file size\s*(?:of\s*)?|size\s*)?:?\s*"# + number,
            number + #"\s*(?:max(?:imum)?|limit|or less|or smaller|maximal|höchstens)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let unitRange = Range(match.range(at: 2), in: line),
                  let value = Double(line[valueRange].replacingOccurrences(of: ",", with: ".")) else { continue }
            let multiplier: Double = switch line[unitRange].lowercased() {
            case "kb": 1_000
            case "gb": 1_000_000_000
            default: 1_000_000
            }
            // Window text is untrusted: "1e400 MB" or a 400-digit number must not trap.
            guard let bytes = FlixNumbers.int64(value * multiplier, in: 1...FlixWindowDemand.largestSizeLimit) else { continue }
            return bytes
        }
        return nil
    }

    /// The objects of request verbs, in reading order, at most five.
    static func wanted(in lines: [String]) -> [FlixWindowDemand.Wanted] {
        var result: [FlixWindowDemand.Wanted] = []
        var seen = Set<String>()
        for line in lines {
            for sentence in line.split(whereSeparator: { ".!?;:\n".contains($0) }) {
                let sentence = String(sentence)
                let lower = sentence.lowercased()
                for verb in requestVerbs {
                    guard let range = wordRange(of: verb, in: lower) else { continue }
                    var tail = String(sentence[range.upperBound...])
                    if tail.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty {
                        tail = String(sentence[..<range.lowerBound])
                    }
                    for piece in split(tail) {
                        let phrase = trimmedPhrase(piece)
                        let keywords = self.keywords(in: phrase)
                        guard !keywords.isEmpty, keywords.count <= 6, seen.insert(keywords.joined(separator: " ")).inserted
                        else { continue }
                        result.append(FlixWindowDemand.Wanted(phrase: phrase, keywords: keywords))
                    }
                    break
                }
                if result.count >= 5 { return Array(result.prefix(5)) }
            }
        }
        return result
    }

    /// Content words of a phrase, lowercased, without stop words or numbers.
    static func keywords(in phrase: String) -> [String] {
        words(in: phrase.lowercased()).filter { word in
            word.count > 1 && !stopWords.contains(word) && !word.allSatisfy(\.isNumber) && !requestVerbs.contains(word)
        }
    }

    static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'’")))
            .map { word in
                // "month's" → "month".
                var word = word
                for suffix in ["'s", "’s"] where word.hasSuffix(suffix) { word = String(word.dropLast(2)) }
                return word.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
            }
            .filter { !$0.isEmpty }
    }

    private static func wordRange(of word: String, in text: String) -> Range<String.Index>? {
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: search) {
            let before = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let after = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if before && after { return range }
            search = range.upperBound..<text.endIndex
        }
        return nil
    }

    /// Splits a clause on "and", "und", "&", and commas.
    private static func split(_ text: String) -> [String] {
        let pattern = #"\s*(?:,|&|\band\b|\bund\b|\bas well as\b|\bsowie\b)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [text] }
        let marked = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\u{1F}")
        return marked.split(separator: "\u{1F}").map(String.init)
    }

    /// Trims a piece to the words the window used: no leading "please", no trailing "here", "below",
    /// "once …", or "to me".
    private static func trimmedPhrase(_ piece: String) -> String {
        var phrase = piece.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for cut in [" once ", " when ", " so ", " before ", " by ", " to me", " to us", " here", " below", " bitte",
                    " sobald ", " wenn ", " bis "] {
            if let range = phrase.range(of: cut, options: .caseInsensitive) { phrase = String(phrase[..<range.lowerBound]) }
        }
        for lead in ["please ", "bitte ", "me ", "us "] where phrase.lowercased().hasPrefix(lead) {
            phrase = String(phrase.dropFirst(lead.count))
        }
        return String(phrase.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).prefix(80))
    }
}
