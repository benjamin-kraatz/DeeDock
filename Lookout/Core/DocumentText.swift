// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// The plain text of the documents Lookout reads without the Cocoa text system: plain and markup text, HTML and XHTML,
/// Safari web archives, subtitles and LaTeX. Pure string work on bytes already read (`QueuedFileGate`), so it runs on
/// any thread, and it lives in `Core`, where the app's tests reach it. `DocExtractor` reads rtf, docx, doc and odt
/// through `NSAttributedString` and everything else here.
///
/// HTML is stripped by pattern, never imported with WebKit or `NSAttributedString`: those must run on the main thread,
/// and the index service reads on a background queue.
nonisolated enum DocumentText {
    /// A web archive that isn't one, or holds no page.
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// The text of a document of the given extension, or nil for the formats `DocExtractor` reads itself.
    ///
    /// - Throws: `Failure` for a web archive that can't be read.
    static func text(of data: Data, fileExtension: String) throws -> String? {
        switch fileExtension.lowercased() {
        case "rtf", "rtfd", "docx", "doc", "odt": nil
        case "html", "htm", "xhtml": plainText(fromHTML: decode(data))
        case "webarchive": try webArchive(data)
        case "srt", "vtt": subtitles(decode(data))
        case "tex", "latex": latex(decode(data))
        default: decode(data)
        }
    }

    /// Plain text in UTF-32 or UTF-16 with a byte-order mark, else UTF-8, else Latin-1, which decodes any bytes.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE, 0, 0]) || data.starts(with: [0, 0, 0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf32) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: HTML

    /// Good enough for search: drops scripts, styles and comments, turns block ends into line breaks, strips the
    /// remaining tags, and decodes common entities.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        for pattern in [#"(?is)<script\b.*?</script\s*>"#, #"(?is)<style\b.*?</style\s*>"#, #"(?s)<!--.*?-->"#,
                        #"(?is)<head\b.*?</head\s*>"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?i)<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\b[^>]*>"#,
                                         with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                        "&apos;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (entity, character) in entities { text = text.replacingOccurrences(of: entity, with: character) }
        text = decodeNumericEntities(text)
        return text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#"), let pattern = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        else { return text }
        var result = ""
        var last = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let codeRange = Range(match.range(at: 1), in: text)
            else { continue }
            let code = text[codeRange]
            let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            result += text[last..<range.lowerBound]
            result += value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? " "
            last = range.upperBound
        }
        return result + text[last...]
    }

    // MARK: Web archives

    /// The text of a Safari web archive: its main resource, a property list's `WebMainResource`, decoded with the
    /// encoding it names and stripped as HTML (`plainText(fromHTML:)`). Subresources (pictures, scripts, frames) are
    /// left out.
    ///
    /// - Throws: `Failure` when the bytes aren't a web archive or it has no main resource.
    static func webArchive(_ data: Data) throws -> String {
        guard let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Failure(description: "not a web archive") }
        guard let main = archive["WebMainResource"] as? [String: Any], let bytes = main["WebResourceData"] as? Data
        else { throw Failure(description: "web archive without a page") }
        let text = (main["WebResourceTextEncodingName"] as? String).flatMap { decode(bytes, charset: $0) }
            ?? decode(bytes)
        let mime = (main["WebResourceMIMEType"] as? String)?.lowercased() ?? "text/html"
        return mime.hasPrefix("text/plain") ? text : plainText(fromHTML: text)
    }

    /// `data` in the IANA character set `charset` ("utf-8", "windows-1252"), or nil when macOS doesn't know it or
    /// the bytes don't fit it.
    private static func decode(_ data: Data, charset: String) -> String? {
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        let converted = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        return String(data: data, encoding: converted)
    }

    // MARK: Subtitles

    /// What's said in a SubRip (`.srt`) or WebVTT (`.vtt`) file: cue numbers, timings, the WebVTT header, `NOTE`,
    /// `STYLE` and `REGION` blocks, and tags such as `<i>`, `<v Speaker>` and `{\an8}` are left out, and each cue's
    /// text becomes one line.
    static func subtitles(_ text: String) -> String {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: #/\n[ \t]*\n/#)
        var spoken: [String] = []
        for block in blocks {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = lines.first else { continue }
            if first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first == "STYLE" || first == "REGION" {
                continue
            }
            // A cue: an optional number or identifier, then the timing line, then its text.
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else {
                if !isCueNumber(first) { spoken.append(contentsOf: lines.map(stripCueTags)) }
                continue
            }
            lines.removeFirst(timing + 1)
            let line = lines.map(stripCueTags).filter { !$0.isEmpty }.joined(separator: " ")
            if !line.isEmpty { spoken.append(line) }
        }
        return spoken.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func isCueNumber(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy(\.isNumber)
    }

    /// One cue line without its formatting: HTML-like tags (`<i>`, `<c.yellow>`, `<00:01.000>`), SSA overrides
    /// (`{\an8}`), and entities.
    private static func stripCueTags(_ line: String) -> String {
        line.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: LaTeX

    /// Commands whose argument is markup, a name or a path rather than words: dropped with it.
    static let latexDroppedArguments: Set<String> = [
        "documentclass", "usepackage", "label", "ref", "eqref", "pageref", "cite", "citep", "citet", "include",
        "input", "includegraphics", "bibliography", "bibliographystyle", "newcommand", "renewcommand",
        "providecommand", "newenvironment", "renewenvironment", "setlength", "addtolength", "setcounter", "hspace",
        "vspace", "begin", "end", "url", "pagestyle", "thispagestyle", "geometry", "hypersetup", "definecolor",
    ]

    /// LaTeX's words: comments, the preamble (when there's a `\begin{document}`), and commands are left out. A
    /// command's braced argument stays, as in `\section{Results}` or `\emph{very}`, except for the commands in
    /// `latexDroppedArguments`. Math delimiters and markup characters go; what's inside stays. Simple on purpose: it
    /// doesn't expand macros.
    static func latex(_ text: String) -> String {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        // Comments: % to the end of the line, unless escaped (\%).
        body = body.replacingOccurrences(of: #"(?m)(?<!\\)%.*$"#, with: "", options: .regularExpression)
        if let start = body.range(of: #"\begin{document}"#) { body = String(body[start.upperBound...]) }
        if let end = body.range(of: #"\end{document}"#) { body = String(body[..<end.lowerBound]) }
        let dropped = latexDroppedArguments.sorted().joined(separator: "|")
        body = body.replacingOccurrences(of: #"\\(?:"# + dropped + #")(?![A-Za-z])\*?(?:\[[^\]]*\])*(?:\{[^{}]*\})*"#,
                                         with: " ", options: .regularExpression)
        // Line breaks; any other command, with an optional argument (its braced argument stays as its words); then
        // the markup characters that aren't escaped.
        body = body.replacingOccurrences(of: #"\\\\"#, with: "\n", options: .regularExpression)
        body = body.replacingOccurrences(of: #"\\[A-Za-z@]+\*?(?:\[[^\]]*\])?"#, with: " ",
                                         options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?<!\\)[{}$^]"#, with: "", options: .regularExpression)
        // The characters people escape, then any other escape.
        for (escaped, character) in [#"\%"#: "%", #"\&"#: "&", #"\$"#: "$", ##"\#"##: "#", #"\_"#: "_",
                                     #"\{"#: "{", #"\}"#: "}"] {
            body = body.replacingOccurrences(of: escaped, with: character)
        }
        body = body.replacingOccurrences(of: #"\\."#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: "~", with: " ")
        return body.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n[ \n]*"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
