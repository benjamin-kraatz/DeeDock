import Foundation

/// Which file names say nothing about the file, and how a suggested name becomes a safe one.
nonisolated enum FlixFileNaming {
    private static let crypticPatterns: [NSRegularExpression] = [
        #"^(screenshot|screen shot|bildschirmfoto|cleanshot|capture|snip|screen recording|bildschirmaufnahme)\b"#,
        #"^(img|dsc|dscn|dcim|pxl|mvimg|photo|image|pic|scan|scanned|vid)[_\- ]?\d"#,
        #"^\d{8}[_\- ]\d{4,6}"#,
        #"^(document|dokument|doc|file|datei|untitled|unbenannt|unnamed|download|attachment|anhang|export|output|neu|new)(\s*\(\d+\)|[_\- ]?\d+)?$"#,
        #"^(image|photo|picture|bild|foto)(\s*\(\d+\))?$"#,
        #"^[0-9a-f]{12,}$"#,
        #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
        #"^[\d_\-\. ()]+$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    /// Whether `name` (with or without its extension) needs a caption to tell what the file is:
    /// screenshots, camera names (`IMG_4821`), `document (3)`, hashes, and digits only.
    static func isCryptic(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty else { return true }
        let range = NSRange(stem.startIndex..., in: stem)
        return crypticPatterns.contains { $0.firstMatch(in: stem, range: range) != nil }
    }

    /// Characters a name never keeps: path separators, Finder's colon, control characters.
    private static let forbidden = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters).union(.newlines)
    /// Longest stem a suggestion keeps, in characters.
    static let maximumStemLength = 80

    /// A safe file name from a suggestion: no path separators, colons, or control characters; no
    /// leading dots or dashes; single spaces; at most ``maximumStemLength`` characters; the
    /// original's extension kept (any extension in the suggestion is dropped); and a name not in
    /// `taken`, by adding " 2", " 3", … before the extension.
    ///
    /// - Parameters:
    ///   - suggestion: The proposed name, with or without an extension.
    ///   - original: The file's current name, whose extension is kept.
    ///   - taken: Names already in the folder, compared ignoring case as the file system does.
    /// - Returns: Nil when nothing usable is left, or the result is the current name.
    static func sanitizedName(_ suggestion: String, keepingExtensionOf original: String,
                              taken: Set<String> = []) -> String? {
        let ext = (original as NSString).pathExtension
        var stem = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ext.isEmpty, (stem as NSString).pathExtension.lowercased() == ext.lowercased() {
            stem = (stem as NSString).deletingPathExtension
        }
        stem = String(stem.unicodeScalars.map { forbidden.contains($0) ? " " : Character($0) })
            .replacingOccurrences(of: "\"", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let first = stem.first, first == "." || first == "-" || first == " " { stem.removeFirst() }
        while let last = stem.last, last == "." || last == " " { stem.removeLast() }
        if stem.count > maximumStemLength {
            stem = String(stem.prefix(maximumStemLength)).trimmingCharacters(in: .whitespaces)
        }
        guard !stem.isEmpty else { return nil }
        let join = { (stem: String) in ext.isEmpty ? stem : stem + "." + ext }
        guard join(stem).lowercased() != original.lowercased() else { return nil }
        let lowered = Set(taken.map { $0.lowercased() })
        var candidate = join(stem)
        var number = 2
        while lowered.contains(candidate.lowercased()) {
            candidate = join("\(stem) \(number)")
            number += 1
        }
        return candidate
    }
}
