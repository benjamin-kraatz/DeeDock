import Foundation

/// Recognizes web documents: pages that are a file you work on rather than a page you read.
///
/// Link tracking keeps a web document once it has stayed in front for ``dwell`` seconds, and the
/// sidebar's **Web documents** kind lists them. Only a page that names one document counts: a Google
/// Docs document, not the Docs home; a Linear issue, not the inbox. The rules read the address only.
nonisolated enum FlixWebDocuments {
    /// How long a web document stays in front before it is kept.
    static let dwell: Duration = .seconds(30)

    /// Which service a web document belongs to.
    enum Service: String, Sendable, CaseIterable {
        case googleDocs, figma, notion, linear, microsoftOffice, atlassian
    }

    /// The service when `url` names a single document there, otherwise nil.
    static func service(for url: URL) -> Service? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let path = url.path(percentEncoded: false)
        func within(_ domain: String) -> Bool { FlixSiteExclusions.host(host, isWithin: domain) }

        if host == "docs.google.com" {
            let kinds: Set<String> = ["document", "spreadsheets", "presentation", "forms", "drawings"]
            // docs.google.com/document/d/<id>/edit, also with a /u/0 account part before or after the kind.
            guard let kind = parts.firstIndex(where: kinds.contains),
                  let marker = parts[kind...].firstIndex(of: "d"), parts.count > marker + 1 else { return nil }
            return .googleDocs
        }
        if within("figma.com") {
            let kinds: Set<String> = ["file", "design", "board", "proto", "slides", "deck", "make"]
            return parts.count >= 2 && kinds.contains(parts[0]) ? .figma : nil
        }
        if within("notion.so") || within("notion.site") || host == "app.notion.com" {
            // A page path ends with its 32-character identifier: /Team/Roadmap-1a2b…
            guard let last = parts.last else { return nil }
            let tail = last.split(separator: "-").last.map(String.init) ?? last
            return tail.count == 32 && tail.allSatisfy(\.isHexDigit) ? .notion : nil
        }
        if host == "linear.app" {
            let kinds: Set<String> = ["issue", "project", "document", "initiative"]
            return parts.count >= 3 && kinds.contains(parts[1]) ? .linear : nil
        }
        if within("sharepoint.com") {
            let markers = ["/:w:/", "/:x:/", "/:p:/", "/:o:/", "Doc.aspx", "WopiFrame", "/_layouts/15/xlviewer"]
            return markers.contains(where: path.contains) ? .microsoftOffice : nil
        }
        if host == "onedrive.live.com" {
            return path.contains("edit") || url.query?.contains("resid=") == true ? .microsoftOffice : nil
        }
        if within("officeapps.live.com") || host == "word.cloud.microsoft" || host == "excel.cloud.microsoft"
            || host == "powerpoint.cloud.microsoft" {
            return .microsoftOffice
        }
        if within("atlassian.net") {
            // Confluence pages and Jira issues.
            if path.contains("/wiki/spaces/") && path.contains("/pages/") { return .atlassian }
            if parts.count >= 2 && parts[0] == "browse" { return .atlassian }
            return nil
        }
        return nil
    }

    static func isWebDocument(_ url: URL) -> Bool { service(for: url) != nil }
}
