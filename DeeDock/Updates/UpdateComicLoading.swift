#if DIRECT_DISTRIBUTION
import Foundation

/// HTTPS and local-file rules for What’s New comic markdown and panel PNGs.
///
/// Remote fetches start only at GitHub Releases or `raw.githubusercontent.com` for
/// `benjamin-kraatz/DeeDock`. Redirects may continue onto `githubusercontent.com`
/// hosts so a release asset can resolve. Local `file` URLs are for previews and tests.
nonisolated enum UpdateComicResourcePolicy {
    nonisolated static let githubOwner = "benjamin-kraatz"
    nonisolated static let githubRepository = "DeeDock"
    nonisolated static let companionMarkdownName = "DDock-comic.md"

    /// Accepts an explicit first-hop URL the app chose, or a local file.
    nonisolated static func allowsInitial(_ url: URL) -> Bool {
        if url.isFileURL { return url.user == nil && url.password == nil }
        return allowsGitHubSource(url)
    }

    /// Accepts a redirect target after an allowlisted first hop.
    nonisolated static func allowsRedirect(_ url: URL) -> Bool {
        if allowsInitial(url) { return true }
        return allowsGitHubusercontent(url)
    }

    /// `DDock-comic.md` in the same directory as Sparkle notes or the enclosure ZIP.
    nonisolated static func companionMarkdownURL(from relatedURL: URL) -> URL? {
        let directory = relatedURL.deletingLastPathComponent()
        guard directory.path != relatedURL.path else { return nil }
        let companion = directory.appendingPathComponent(companionMarkdownName)
        return allowsInitial(companion) ? companion : nil
    }

    /// Relative art path against the comic document, plus a same-directory `panel-0N.png` fallback.
    nonisolated static func imageCandidates(path: String, documentURL: URL) -> [URL] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let directory = documentURL.deletingLastPathComponent()
        var candidates: [URL] = []
        if let resolved = URL(string: trimmed, relativeTo: directory)?.absoluteURL {
            candidates.append(resolved)
        }
        let filename = URL(fileURLWithPath: trimmed).lastPathComponent
        if isPanelFilename(filename) {
            candidates.append(directory.appendingPathComponent(filename))
        }
        var seen = Set<String>()
        return candidates.filter { url in
            guard allowsInitial(url), seen.insert(url.absoluteString).inserted else { return false }
            return true
        }
    }

    nonisolated static func isPanelFilename(_ name: String) -> Bool {
        let lowered = name.lowercased()
        guard lowered.hasPrefix("panel-"), lowered.hasSuffix(".png") else { return false }
        let digits = lowered.dropFirst(6).dropLast(4)
        return digits.count == 2 && digits.allSatisfy(\.isNumber)
    }

    nonisolated private static func allowsGitHubSource(_ url: URL) -> Bool {
        guard isBareHTTPS(url), let host = url.host?.lowercased() else { return false }
        let path = normalizedPath(url)
        let repo = "/\(githubOwner)/\(githubRepository)"
        if host == "github.com" {
            return path.hasPrefix("\(repo)/releases/download/")
                || path.hasPrefix("\(repo)/releases/latest/download/")
        }
        if host == "raw.githubusercontent.com" {
            return path.hasPrefix("\(repo)/")
        }
        return false
    }

    nonisolated private static func allowsGitHubusercontent(_ url: URL) -> Bool {
        guard isBareHTTPS(url), let host = url.host?.lowercased() else { return false }
        return host == "githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    nonisolated private static func isBareHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    nonisolated private static func normalizedPath(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        if path.count > 1, path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }
}

/// Fetches companion comic markdown and panel PNGs with the notes size bound and a per-image cap.
nonisolated enum UpdateComicLoader {
    nonisolated static let maximumImageBytes = 2 * 1024 * 1024

    /// Loads `DDock-comic.md` next to `relatedURL` and fills panel `imageData` when art succeeds.
    ///
    /// Failures stay soft: a missing file, a rejected host, or a bad PNG leaves `imageData` nil
    /// and still returns copy when the markdown parsed. Cancellation discards the result.
    @concurrent static func load(fromRelatedURL relatedURL: URL) async -> UpdateComic? {
        guard let markdownURL = UpdateComicResourcePolicy.companionMarkdownURL(from: relatedURL),
              let data = await download(markdownURL, limit: UpdateReleaseNotes.maximumBytes),
              let text = String(data: data, encoding: .utf8),
              !Task.isCancelled,
              var comic = UpdateComicParser.parse(text) else { return nil }
        for index in comic.panels.indices {
            guard !Task.isCancelled else { return nil }
            comic.panels[index].imageData = await firstImage(for: comic.panels[index].imagePath,
                                                             documentURL: markdownURL)
        }
        return comic
    }

    @concurrent private static func firstImage(for path: String, documentURL: URL) async -> Data? {
        for candidate in UpdateComicResourcePolicy.imageCandidates(path: path, documentURL: documentURL) {
            guard !Task.isCancelled else { return nil }
            if let data = await download(candidate, limit: maximumImageBytes), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    @concurrent private static func download(_ url: URL, limit: Int) async -> Data? {
        if url.isFileURL {
            guard UpdateComicResourcePolicy.allowsInitial(url),
                  let data = try? Data(contentsOf: url),
                  data.count <= limit else { return nil }
            return data
        }
        guard UpdateComicResourcePolicy.allowsInitial(url) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard data.count <= limit else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: UpdateComicRedirectGate(),
                          delegateQueue: nil)
    }()
}

/// Drops redirects that leave the GitHub allowlist after an explicit first hop.
/// The type holds no mutable state. URLSession retains one instance.
nonisolated private final class UpdateComicRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, UpdateComicResourcePolicy.allowsRedirect(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
#endif
