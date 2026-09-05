#if DIRECT_DISTRIBUTION
import Foundation

/// Converts release text into native attributed text. HTML is parsed as an inert document,
/// never executed or displayed in a browser, and external entities and non-HTTPS links are rejected.
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
    @concurrent static func render(_ text: String, format: String) async -> AttributedString? {
        guard text.utf8.count <= maximumBytes, !Task.isCancelled else { return nil }
        let format = format.lowercased()
        let markdown: String
        if format.contains("html") {
            guard let document = try? XMLDocument(xmlString: text,
                options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
                  let root = document.rootElement() else { return nil }
            markdown = htmlText(root)
        } else if format.contains("markdown") {
            // Preserve paragraph breaks while giving Markdown headings and lists native emphasis.
            markdown = text.replacingOccurrences(of: "(?m)^#{1,6} +(.+?) *#* *$", with: "**$1**", options: .regularExpression)
                .replacingOccurrences(of: "(?m)^[-+*] +", with: "• ", options: .regularExpression)
        } else {
            return AttributedString(text)
        }
        guard !Task.isCancelled, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var result = try? AttributedString(markdown: markdown,
                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return nil }
        // Native Text only exposes explicitly safe external links, including in Markdown feeds.
        for run in result.runs {
            if let link = run.link, safeLink(link) == nil { result[run.range].link = nil }
        }
        return result
    }

    nonisolated private static func htmlText(_ node: XMLNode, depth: Int = 0) -> String {
        guard depth < 64, !Task.isCancelled else { return "" }
        if node.kind == .text { return escape(node.stringValue ?? "") }
        let name = node.name?.lowercased() ?? ""
        if ["script", "style", "head", "iframe", "object", "embed", "svg", "form"].contains(name) { return "" }
        let content = (node.children ?? []).map { htmlText($0, depth: depth + 1) }.joined()
        switch name {
        case "br": return "\n"
        case "p", "div", "section", "ul", "ol", "blockquote", "pre", "table": return "\n\n" + content + "\n\n"
        case "li": return "\n• " + content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        case "h1", "h2", "h3", "h4", "h5", "h6": return "\n\n**" + content + "**\n\n"
        case "strong", "b": return "**" + content + "**"
        case "em", "i": return "*" + content + "*"
        case "tr": return "\n" + content + "\n"
        case "td", "th": return content + "  "
        case "a":
            guard let raw = (node as? XMLElement)?.attribute(forName: "href")?.stringValue,
                  let url = safeLink(URL(string: raw)) else { return content }
            // Encoding delimiters keeps a remote URL from introducing Markdown syntax.
            let destination = url.absoluteString.replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            return "[" + content + "](" + destination + ")"
        default: return content
        }
    }

    nonisolated private static func escape(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "\\`*_{}[]<>".contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}
#endif
