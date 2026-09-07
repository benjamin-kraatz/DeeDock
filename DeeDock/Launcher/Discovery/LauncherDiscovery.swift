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
        var applications: [String: LauncherApplication] = [:]
        for url in urls.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            guard let application = read(url), applications[application.id] == nil else { continue }
            applications[application.id] = application
        }
        return Snapshot(applications: applications.values.sorted { $0.reference.name.localizedStandardCompare($1.reference.name) == .orderedAscending }, skippedDirectories: skipped)
    }

    private static func read(_ url: URL) -> LauncherApplication? {
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
        return LauncherApplication(reference: reference, category: info["LSApplicationCategoryType"] as? String ?? "", aliases: aliases)
    }

    /// Spotlight also indexes framework helpers, caches named .app, and device build products.
    /// Known pins and running-app URLs bypass this location filter, but still require a runnable Mac bundle.
    static func isUserFacingLocation(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        let components = url.pathComponents.dropLast()
        if components.contains(where: { ["app", "framework", "bundle", "xpc"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) { return false }
        if components.contains(where: { [".Trash", ".Trashes", ".git", "node_modules", "DerivedData"].contains($0) }) { return false }
        if path.hasPrefix(home.appendingPathComponent("Library").path + "/") || path.hasPrefix("/Library/") { return false }
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
