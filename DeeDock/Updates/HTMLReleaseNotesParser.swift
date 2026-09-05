#if DIRECT_DISTRIBUTION
import Foundation

/// HTML structure becomes native blocks directly. Markup is never round-tripped through Markdown.
nonisolated enum HTMLReleaseNotesParser {
    private static let ignored = Set(["script", "style", "head", "iframe", "object", "embed", "svg", "form"])

    static func parse(_ html: String) -> [UpdateReleaseNoteBlock] {
        guard let document = try? XMLDocument(xmlString: html,
            options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return [] }
        return blocks(in: [root])
    }

    private static func blocks(in nodes: [XMLNode], indentation: Int = 0, depth: Int = 0) -> [UpdateReleaseNoteBlock] {
        guard depth < 64, !Task.isCancelled else { return [] }
        var result: [UpdateReleaseNoteBlock] = []
        var pending = AttributedString()
        func flush() {
            let text = UpdateReleaseNotes.trimmed(pending)
            if !text.characters.isEmpty { result.append(UpdateReleaseNoteBlock(text: text, indentation: indentation)) }
            pending = AttributedString()
        }
        for node in nodes {
            let name = node.name?.lowercased() ?? ""
            if ignored.contains(name) { continue }
            let children = node.children ?? []
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                let text = UpdateReleaseNotes.trimmed(inline(node))
                if !text.characters.isEmpty {
                    result.append(UpdateReleaseNoteBlock(style: .heading(Int(name.suffix(1)) ?? 2),
                                                         text: text, indentation: indentation))
                }
            case "pre":
                flush()
                let text = (node.stringValue ?? "").trimmingCharacters(in: .newlines)
                if !text.isEmpty { result.append(UpdateReleaseNoteBlock(style: .code, text: AttributedString(text), indentation: indentation)) }
            case "ul", "ol":
                flush()
                var ordinal = Int((node as? XMLElement)?.attribute(forName: "start")?.stringValue ?? "") ?? 1
                for item in children where item.name?.lowercased() == "li" {
                    var entries = blocks(in: item.children ?? [], indentation: indentation + 1, depth: depth + 1)
                    if !entries.isEmpty {
                        entries[0].marker = name == "ol" ? "\(ordinal)." : "•"
                        entries[0].indentation = indentation
                        result += entries
                    }
                    if ordinal < Int.max { ordinal += 1 }
                }
            case "html", "body", "div", "section", "article", "p", "blockquote", "table", "tbody", "tr":
                flush()
                result += blocks(in: children, indentation: indentation, depth: depth + 1)
            default:
                pending.append(inline(node))
            }
        }
        flush()
        return result
    }

    private static func inline(_ node: XMLNode, depth: Int = 0) -> AttributedString {
        guard depth < 64, !Task.isCancelled else { return AttributedString() }
        if node.kind == .text {
            // TidyHTML inserts indentation/newlines even inside headings. HTML collapses that
            // whitespace; retaining it would create visible gaps and break inline emphasis.
            return AttributedString((node.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
        }
        let name = node.name?.lowercased() ?? ""
        if ignored.contains(name) { return AttributedString() }
        if name == "br" { return AttributedString("\n") }
        var text = (node.children ?? []).reduce(into: AttributedString()) { $0.append(inline($1, depth: depth + 1)) }
        let intent: InlinePresentationIntent?
        switch name {
        case "strong", "b": intent = .stronglyEmphasized
        case "em", "i": intent = .emphasized
        case "code": intent = .code
        default: intent = nil
        }
        if let intent {
            for run in text.runs { text[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent) }
        }
        if name == "a", let href = (node as? XMLElement)?.attribute(forName: "href")?.stringValue,
           let url = UpdateReleaseNotes.safeLink(URL(string: href)) { text.link = url }
        return text
    }
}
#endif
