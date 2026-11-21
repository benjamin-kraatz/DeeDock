import Foundation

/// Word handling shared by search, Threads, version families, and folder rules: splitting names
/// into comparable words, a light stem, and the generic file words (English and German) that say
/// nothing about what a file is about.
nonisolated enum FlixWords {
    /// Words every kind of file name uses: "Screenshot", "IMG", "final", "Kopie". They never make
    /// two files related.
    static let generic: Set<String> = [
        "screenshot", "screen", "shot", "bildschirmfoto", "img", "image", "images", "photo", "foto", "pic", "dsc",
        "pxl", "document", "documents", "dokument", "doc", "docs", "file", "files", "datei", "dateien", "untitled",
        "unbenannt", "unnamed", "new", "neu", "neue", "copy", "kopie", "final", "draft", "entwurf", "version",
        "rev", "revision", "signed", "unterschrieben", "scan", "scanned", "export", "download", "downloads",
        "attachment", "anhang", "the", "and", "und", "der", "die", "das", "for", "fur", "für", "with", "mit", "from",
        "von", "pdf", "png", "jpg", "jpeg", "heic", "docx", "xlsx", "pptx", "key", "pages", "numbers", "zip", "txt",
        "at", "am", "um", "on", "of", "in", "im", "to", "a", "an", "es",
    ]

    /// Lowercased words of `text`, split on anything but letters, digits, and `&`, with diacritics
    /// folded ("Präsentation" → "prasentation"). Keeps numbers.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !($0.isLetter || $0.isNumber || $0 == "&") }
            .map(String.init)
            .filter { $0 != "&" }
    }

    /// The words of a file name (without its extension) that can tie it to other files: no generic
    /// words, no pure numbers, at least three characters, stemmed.
    static func distinctive(_ name: String) -> Set<String> {
        let stem = (name as NSString).deletingPathExtension
        return Set(words(stem).filter { word in
            word.count >= 3 && !generic.contains(word) && !word.allSatisfy(\.isNumber)
                && !(word.first == "v" && word.dropFirst().allSatisfy(\.isNumber))
        }.map(Self.stem))
    }

    /// A light stem good enough for matching typed words against names: drops a plural "s" or "es"
    /// and German "en"/"n" endings on longer words. "invoices" and "invoice" meet; so do
    /// "Rechnungen" and "Rechnung".
    static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ungen") { return String(word.dropLast(2)) }
        if ["sses", "xes", "zes", "ches", "shes"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        if word.hasSuffix("en"), word.count > 6 { return String(word.dropLast(2)) }
        return word
    }

    /// Whether `haystack` contains every one of `words`, each compared by its stem, ignoring case and
    /// diacritics.
    static func containsAll(_ words: [String], in haystack: String) -> Bool {
        let folded = haystack.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return !words.isEmpty && words.allSatisfy { folded.contains(stem($0)) }
    }
}
