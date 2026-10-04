import Foundation

/// Fetches short App Store descriptions through Apple's public iTunes Lookup endpoint and caches them on disk.
///
/// Only called for apps installed from the Mac App Store (they carry a `_MASReceipt`), so the request names
/// apps Apple already has in the user's purchase history. Results, including "not found", are cached for
/// `lifetime` in `Application Support/DDock/Launcher/AppStoreDescriptions.json`; a failed request is not
/// cached and is retried on the next Robi request.
actor LauncherAppStoreLookup {
    private nonisolated struct Entry: Codable {
        var description: String?
        var fetched: Date
    }

    private nonisolated struct Response: Decodable {
        struct Result: Decodable {
            let bundleId: String?
            let description: String?
        }
        let results: [Result]
    }

    private let cacheURL: URL?
    private let session: URLSession
    private let lifetime: TimeInterval = 30 * 24 * 60 * 60
    private var cache: [String: Entry]?

    /// - Parameter cacheURL: Cache file location; `nil` keeps results in memory only.
    init(cacheURL: URL? = LauncherAppStoreLookup.defaultCacheURL, session: URLSession = .shared) {
        self.cacheURL = cacheURL
        self.session = session
    }

    nonisolated static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DDock/Launcher/AppStoreDescriptions.json")
    }

    /// Returns condensed descriptions keyed by bundle identifier for those the App Store knows.
    ///
    /// Fresh cache entries are used without a request. Missing or expired identifiers are fetched in batches;
    /// the first network failure or cancellation stops fetching and returns what is already known. Never throws.
    func descriptions(for bundleIdentifiers: [String]) async -> [String: String] {
        var cache = loadCache()
        let now = Date()
        let stale = bundleIdentifiers.filter { identifier in
            cache[identifier].map { now.timeIntervalSince($0.fetched) > lifetime } ?? true
        }
        var changed = false
        for start in stride(from: 0, to: stale.count, by: 50) {
            let batch = Array(stale[start..<min(start + 50, stale.count)])
            guard !Task.isCancelled, let found = await fetch(batch) else { break }
            for identifier in batch { cache[identifier] = Entry(description: found[identifier], fetched: now) }
            changed = true
        }
        self.cache = cache
        if changed { saveCache(cache) }
        return bundleIdentifiers.reduce(into: [:]) { result, identifier in
            if let description = cache[identifier]?.description { result[identifier] = description }
        }
    }

    /// Returns `nil` when the request fails, so the batch is not cached as "not found".
    private func fetch(_ bundleIdentifiers: [String]) async -> [String: String]? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifiers.joined(separator: ",")),
                                 URLQueryItem(name: "entity", value: "macSoftware"),
                                 URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let requested = Set(bundleIdentifiers)
        var found: [String: String] = [:]
        for result in decoded.results {
            // The endpoint also returns iOS records; keep only identifiers that were asked for.
            guard let identifier = result.bundleId, requested.contains(identifier),
                  let description = result.description.map(Self.condense), !description.isEmpty else { continue }
            found[identifier] = description
        }
        return found
    }

    /// Store descriptions run to thousands of characters; the opening paragraph usually states the purpose.
    /// Keeping ~160 characters lets a 25-app prompt fit the on-device model's context window.
    private nonisolated static func condense(_ text: String) -> String {
        let paragraph = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let words = paragraph.split(whereSeparator: \.isWhitespace)
        var result = ""
        for word in words {
            guard result.count + word.count < 160 else { return result + "…" }
            result += result.isEmpty ? String(word) : " " + word
        }
        return result
    }

    private func loadCache() -> [String: Entry] {
        if let cache { return cache }
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }

    private func saveCache(_ cache: [String: Entry]) {
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
