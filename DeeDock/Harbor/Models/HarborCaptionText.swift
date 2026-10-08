import Foundation

/// Turns a window's Accessibility document into the second caption line under its thumbnail.
///
/// The line answers "where is this?" the way the Finder's path bar does: the folder of a
/// document, the full path of a Finder window, or the host and path of a web page. Pure, so the
/// rule is testable without windows.
nonisolated enum HarborCaptionText {
    /// - Parameters:
    ///   - document: The raw `AXDocument` value, usually a `file://` or `https://` URL.
    ///   - title: The window title, used to tell a document window from a folder window.
    /// - Returns: A short path or address, or nil when the document adds nothing to the title.
    static func subtitle(document: String?, title: String?) -> String? {
        guard let document, let url = URL(string: document) ?? URL(string: document.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            return nil
        }
        if url.isFileURL {
            return filePath(url, title: title)
        }
        guard let host = url.host(), url.scheme?.hasPrefix("http") == true else { return nil }
        var path = url.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        let shown = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return shown + path
    }

    /// A document window shows its folder; a folder window shows itself. Both abbreviate the
    /// home folder to `~`, as the Finder's Go menu does.
    private static func filePath(_ url: URL, title: String?) -> String? {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        let isDocument = title.map { $0 == name || $0.hasPrefix(name + " ") } ?? true
        let shown = isDocument ? standardized.deletingLastPathComponent() : standardized
        let path = shown.path(percentEncoded: false)
        guard !path.isEmpty, path != "/" else { return nil }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
