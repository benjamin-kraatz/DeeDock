#if DIRECT_DISTRIBUTION
import Foundation

/// A semantic text block gives SwiftUI control of spacing, typography and hanging list indents.
nonisolated struct UpdateReleaseNoteBlock: Identifiable, Sendable {
    enum Style: Sendable { case paragraph, heading(Int), code }
    var id = 0
    var style: Style = .paragraph
    var text: AttributedString
    var marker: String? = nil
    var indentation = 0
}

/// Parses release notes without executing HTML or loading remote resources.
enum UpdateReleaseNotes {
    nonisolated static let maximumBytes = 512 * 1024

    nonisolated static func safeLink(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    nonisolated static func decode(_ data: Data, encodingName: String?) -> String? {
        if let encodingName {
            let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if encoding != kCFStringEncodingInvalidId {
                return String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
            }
        }
        return String(data: data, encoding: .utf8)
    }

    /// Parsing stays off the main actor; the driver cancels/discards results from older offers.
    @concurrent static func render(_ text: String, format: String) async -> [UpdateReleaseNoteBlock]? {
        guard text.utf8.count <= maximumBytes, !Task.isCancelled else { return nil }
        let blocks: [UpdateReleaseNoteBlock]
        if format.lowercased().contains("html") {
            blocks = HTMLReleaseNotesParser.parse(text)
        } else {
            blocks = textBlocks(text, markdown: format.lowercased().contains("markdown"))
        }
        guard !Task.isCancelled, !blocks.isEmpty else { return nil }
        return blocks.enumerated().map { index, block in
            var block = block
            block.id = index
            return block
        }
    }

    /// Trims block boundaries without removing inline formatting or explicit line breaks.
    nonisolated static func trimmed(_ text: AttributedString) -> AttributedString {
        var text = text
        while text.characters.first?.isWhitespace == true {
            text.removeSubrange(text.startIndex..<text.characters.index(after: text.startIndex))
        }
        while text.characters.last?.isWhitespace == true {
            text.removeSubrange(text.characters.index(before: text.endIndex)..<text.endIndex)
        }
        return text
    }

    nonisolated private static func inlineMarkdown(_ text: String) -> AttributedString {
        var result = (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in result.runs {
            if let link = run.link, safeLink(link) == nil { result[run.range].link = nil }
        }
        return result
    }

    nonisolated private static func textBlocks(_ text: String, markdown: Bool) -> [UpdateReleaseNoteBlock] {
        var blocks: [UpdateReleaseNoteBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                blocks.append(UpdateReleaseNoteBlock(text: markdown ? inlineMarkdown(value) : AttributedString(value)))
            }
            paragraph.removeAll()
        }
        for rawLine in text.components(separatedBy: .newlines) {
            guard !Task.isCancelled else { return [] }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if markdown, line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                if let contents = code {
                    blocks.append(UpdateReleaseNoteBlock(style: .code, text: AttributedString(contents.joined(separator: "\n"))))
                    code = nil
                } else { code = [] }
            } else if code != nil {
                code?.append(rawLine)
            } else if line.isEmpty {
                flush()
            } else if markdown, let range = line.range(of: "^#{1,6} +", options: .regularExpression) {
                flush()
                let level = line[range].filter { $0 == "#" }.count
                let value = String(line[range.upperBound...])
                blocks.append(UpdateReleaseNoteBlock(style: .heading(level), text: inlineMarkdown(value)))
            } else if markdown, let range = line.range(of: "^([-+*]|[0-9]+[.)]) +", options: .regularExpression) {
                flush()
                let prefix = line[range].trimmingCharacters(in: .whitespaces)
                let marker = prefix.first?.isNumber == true ? prefix : "•"
                blocks.append(UpdateReleaseNoteBlock(text: inlineMarkdown(String(line[range.upperBound...])),
                    marker: marker, indentation: min(8, rawLine.prefix(while: { $0 == " " }).count / 2)))
            } else {
                paragraph.append(rawLine)
            }
        }
        flush()
        if let code { blocks.append(UpdateReleaseNoteBlock(style: .code, text: AttributedString(code.joined(separator: "\n")))) }
        return blocks
    }
}
#endif
