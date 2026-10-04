import Foundation

/// Scans application directories even when Spotlight is disabled. Never descends into bundles.
nonisolated enum LauncherDiscovery {
    struct Snapshot: Sendable {
        let applications: [LauncherApplication]
        let skippedDirectories: Int
    }

    @concurrent static func scan(extraURLs: [URL]) async throws -> Snapshot {
        try scanDirectories(extraURLs: extraURLs)
    }

    private static func scanDirectories(extraURLs: [URL]) throws -> Snapshot {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"),
                     manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications"),
                     URL(fileURLWithPath: "/System/Library/CoreServices/Applications")]
        var urls = extraURLs
        var skipped = 0
        for root in roots where manager.fileExists(atPath: root.path) {
            try Task.checkCancellation()
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else {
                skipped += 1; continue
            }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                if url.pathExtension.lowercased() == "app" { urls.append(url); enumerator.skipDescendants() }
            }
        }
        let nested = nestedURLs(urls, home: manager.homeDirectoryForCurrentUser)
        var candidates: [LauncherApplication] = []
        for url in urls.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            if let application = read(url, isNested: nested.contains(url)) { candidates.append(application) }
        }
        return Snapshot(applications: deduplicated(candidates).sorted { $0.reference.name.localizedStandardCompare($1.reference.name) == .orderedAscending }, skippedDirectories: skipped)
    }

    /// Keeps one copy per ``LauncherApplication/id``, preferring a copy that is not nested.
    ///
    /// Copies of one bundle share an id, and the Launcher hides nested copies by default. If a nested
    /// copy won, the top-level install would vanish and Show Nested Apps would only reveal the nested
    /// one. Among copies with the same nesting, the first in `candidates` wins, so the scan's path
    /// order keeps results stable. The result is unordered.
    static func deduplicated(_ candidates: [LauncherApplication]) -> [LauncherApplication] {
        var applications: [String: LauncherApplication] = [:]
        for candidate in candidates {
            if let kept = applications[candidate.id], !kept.isNested || candidate.isNested { continue }
            applications[candidate.id] = candidate
        }
        return Array(applications.values)
    }

    /// Returns the bundles under an Applications folder that sit in a subfolder of a directory that
    /// directly holds another `.app`.
    ///
    /// Unity installs `Unity.app` into `/Applications/Unity/Hub/Editor/<version>/` and a dozen
    /// `UnityPlayer.app` build templates further down under `PlaybackEngines/`. Those templates are
    /// nested; `Unity Bug Reporter.app`, a sibling of `Unity.app`, is not. The Applications root itself
    /// never counts as a holding folder, so `/Applications/Utilities/Terminal.app` stays top level.
    ///
    /// Uses every enumerated URL, before ``deduplicated(_:)`` drops other copies of the parent app.
    /// Lexical only, so it adds no filesystem work to the scan.
    static func nestedURLs(_ urls: [URL], home: URL) -> Set<URL> {
        let roots = LauncherLocationFilter.applicationsRoots(home: home)
        let paths = urls.map { LauncherLocationFilter.comparablePath($0) }
        let holdingFolders = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        var nested: Set<URL> = []
        for (url, path) in zip(urls, paths) {
            guard let root = roots.first(where: { path.hasPrefix($0 + "/") }) else { continue }
            // Start above the app's own folder: siblings in one folder are peers, not nested.
            var folder = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            while folder.hasPrefix(root + "/") {
                if holdingFolders.contains(folder) { nested.insert(url); break }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return nested
    }

    private static func read(_ url: URL, isNested: Bool) -> LauncherApplication? {
        guard url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.path),
              let bundle = Bundle(url: url), let info = bundle.infoDictionary,
              (info["CFBundlePackageType"] as? String ?? "APPL") == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path),
              !flag(info["LSUIElement"]), !flag(info["LSBackgroundOnly"]) else { return nil }
        if let platforms = info["CFBundleSupportedPlatforms"] as? [String],
           !platforms.contains(where: { $0.lowercased() == "macosx" || $0.lowercased() == "macos" }) { return nil }
        let localized = bundle.localizedInfoDictionary ?? [:]
        let fallback = url.deletingPathExtension().lastPathComponent
        let name = localized["CFBundleDisplayName"] as? String ?? localized["CFBundleName"] as? String
            ?? info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? fallback
        let reference = ApplicationReference(bundleIdentifier: bundle.bundleIdentifier, url: url, name: name)
        let aliases = [info["CFBundleName"], info["CFBundleDisplayName"], info["CFBundleExecutable"]].compactMap { $0 as? String }
        return LauncherApplication(reference: reference, category: info["LSApplicationCategoryType"] as? String ?? "",
                                   capabilities: LauncherAppCapabilities.summary(info: info), aliases: aliases, isNested: isNested)
    }

    /// Spotlight also indexes framework helpers, caches named .app, and device build products.
    /// Known pins and running-app URLs bypass this location filter, but still require a runnable Mac bundle.
    /// Runs on every Spotlight result when the Launcher opens, so it uses lexical path checks only.
    /// `standardizedFileURL` and `URL(fileURLWithPath:)` both query the file system.
    static func isUserFacingLocation(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardized.path
        let components = (path as NSString).pathComponents.dropLast()
        if components.contains(where: { ["app", "framework", "bundle", "xpc"].contains(($0 as NSString).pathExtension.lowercased()) }) { return false }
        if components.contains(where: { [".Trash", ".Trashes", ".git", "node_modules", "DerivedData"].contains($0) }) { return false }
        if path.hasPrefix(home.standardized.path + "/Library/") || path.hasPrefix("/Library/") { return false }
        if path.hasPrefix("/System/") {
            return path.hasPrefix("/System/Applications/")
                || path.hasPrefix("/System/Library/CoreServices/Applications/")
                || path == "/System/Library/CoreServices/Finder.app"
        }
        return true
    }

    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return false
    }
}
