import AppKit
import Observation

/// Site icons for link rows, fetched only while **Load site icons** is on.
///
/// Off (the default), rows draw a monogram and no request is made. On, the first row for a host asks
/// `https://<host>/favicon.ico` once, with an ephemeral session (no cookies, no cache shared with
/// browsers), a five-second timeout, and a 256 KB cap. Icons are kept in memory and in DOKK's caches
/// folder; a host that failed is not asked again this session. Main actor; the request runs in a
/// task this store owns, and ``stop()`` cancels them.
@MainActor @Observable
final class FlixSiteIconStore {
    static let shared = FlixSiteIconStore()

    var isEnabled = false {
        didSet { if !isEnabled { cancelAll() } }
    }

    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private var attempted = Set<String>()
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private lazy var session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return configuration
    }())

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: (Bundle.main.bundleIdentifier ?? "DeeDock") + "/FlixSiteIcons", directoryHint: .isDirectory)
    }

    /// The icon for `host` when one was loaded and icons are on. Nil draws the monogram.
    func icon(for host: String) -> NSImage? {
        isEnabled ? icons[host] : nil
    }

    /// Starts loading `host`'s icon when allowed and not tried yet. Called from a view's task, never
    /// from a body.
    func request(_ host: String) {
        guard isEnabled, !host.isEmpty, icons[host] == nil, attempted.insert(host).inserted else { return }
        load(host)
    }

    func stop() {
        cancelAll()
    }

    private func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    private func load(_ host: String) {
        let file = Self.folder.appending(path: host + ".ico")
        let session = session
        tasks[host] = Task { [weak self] in
            let data = await Self.data(for: host, cached: file, session: session)
            guard let self, !Task.isCancelled else { return }
            tasks[host] = nil
            if let data, let image = NSImage(data: data), image.isValid { icons[host] = image }
        }
    }

    @concurrent
    private static func data(for host: String, cached file: URL, session: URLSession) async -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        guard let url = URL(string: "https://\(host)/favicon.ico"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= 256 * 1_024 else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}
