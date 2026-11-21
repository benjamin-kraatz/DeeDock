import AppKit

/// A browser engine family, which decides how Flix reads a page address and whether it can tell a
/// private window from a normal one.
nonisolated enum FlixBrowserFamily: String, Sendable {
    /// Safari and Safari Technology Preview.
    case safari
    /// Chrome, Edge, Brave, Vivaldi, Opera, Arc, Helium, Chromium, and other Chromium builds.
    case chromium
    /// Firefox and its forks (Zen, LibreWolf, Floorp, Waterfox).
    case firefox
    /// Any other app that opens web addresses (Orion, DuckDuckGo, …).
    case other

    /// Whether link tracking may record this family's pages on its own (window title changes,
    /// dwell times, drops).
    ///
    /// Only families with a private-window check (``FlixBrowserPageReader``) qualify. Safari exposes
    /// no private-window signal in its accessibility tree that DOKK could verify, so Safari pages
    /// are kept only when you save them ("Save this page", a dropped URL) or download from them.
    var tracksAutomatically: Bool {
        switch self {
        case .chromium, .firefox: true
        case .safari, .other: false
        }
    }
}

/// Which running apps are browsers: an app is a browser when Launch Services says it opens `https:`
/// addresses. The family comes from the bundle identifier, then from the engine the bundle ships
/// (Chromium's `chrome_100_percent.pak`, Firefox's `XUL`). Cached per bundle. Main actor.
@MainActor
enum FlixBrowserCatalog {
    private static var families: [URL: FlixBrowserFamily?] = [:]

    static let safariBundles: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let firefoxPrefixes = ["org.mozilla.", "app.zen-browser.", "io.gitlab.librewolf", "one.ablaze.floorp", "net.waterfox."]
    static let chromiumPrefixes = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
                                   "com.operasoftware.", "org.chromium.", "company.thebrowser.", "net.imput.helium",
                                   "ai.perplexity.comet", "com.sigmaos.", "com.naver.Whale", "ru.yandex.desktop.yandex-browser"]

    /// The browser family of `app`, or nil when it is not a browser.
    static func family(of app: NSRunningApplication) -> FlixBrowserFamily? {
        guard let url = app.bundleURL?.standardizedFileURL else { return nil }
        if let known = families[url] { return known }
        let family = classify(bundleIdentifier: app.bundleIdentifier, bundleURL: url)
        families[url] = family
        return family
    }

    static func family(processIdentifier: pid_t) -> FlixBrowserFamily? {
        NSRunningApplication(processIdentifier: processIdentifier).flatMap(family(of:))
    }

    private static func classify(bundleIdentifier: String?, bundleURL: URL) -> FlixBrowserFamily? {
        guard FlixAppCategory.of(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL) == .browser else { return nil }
        let id = bundleIdentifier ?? ""
        if safariBundles.contains(id) { return .safari }
        if firefoxPrefixes.contains(where: id.hasPrefix) { return .firefox }
        if chromiumPrefixes.contains(where: id.hasPrefix) { return .chromium }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: bundleURL.appending(path: "Contents/MacOS/XUL").path) { return .firefox }
        let frameworks = bundleURL.appending(path: "Contents/Frameworks")
        let names = (try? fileManager.contentsOfDirectory(atPath: frameworks.path)) ?? []
        if names.contains(where: { name in
            name.hasSuffix(".framework") && fileManager.fileExists(
                atPath: frameworks.appending(path: "\(name)/Resources/chrome_100_percent.pak").path)
        }) { return .chromium }
        return .other
    }

    /// Forgets cached answers, for when apps were installed or updated.
    static func invalidate() {
        families = [:]
        FlixAppCategory.invalidate()
    }
}
