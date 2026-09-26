import Foundation

/// File format for saved markups. Copying always uses PNG so the clipboard keeps redactions crisp.
nonisolated enum WindowMarkupFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg

    var title: LocalizedStringResource {
        switch self {
        case .png: .markupFormatPNG
        case .jpeg: .markupFormatJPEG
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

/// Where **Search Web** sends recognised text. macOS exposes no public API for the browser's own
/// default engine, so the choice lives here.
nonisolated enum WindowMarkupSearchEngine: String, Codable, CaseIterable, Sendable {
    case google, duckDuckGo, bing, ecosia

    var title: LocalizedStringResource {
        switch self {
        case .google: .markupSearchEngineGoogle
        case .duckDuckGo: .markupSearchEngineDuckDuckGo
        case .bing: .markupSearchEngineBing
        case .ecosia: .markupSearchEngineEcosia
        }
    }

    /// The results page for `query`, or `nil` for an empty query.
    func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components: URLComponents
        switch self {
        case .google: components = URLComponents(string: "https://www.google.com/search")!
        case .duckDuckGo: components = URLComponents(string: "https://duckduckgo.com/")!
        case .bing: components = URLComponents(string: "https://www.bing.com/search")!
        case .ecosia: components = URLComponents(string: "https://www.ecosia.org/search")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: String(trimmed.prefix(1_000)))]
        return components.url
    }
}

/// Resolves the folder markups are written to when the user does not name one in a panel.
nonisolated enum WindowMarkupFolder {
    static let defaultName = "DeeDock Markups"

    /// `~/Pictures/DeeDock Markups` unless Settings names another folder.
    static func url(configured path: String?, fileManager: FileManager = .default) -> URL {
        if let path, !path.isEmpty { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent(defaultName, isDirectory: true)
    }
}
