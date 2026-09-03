import AppKit

/// Main-actor adapter for app discovery, icon caching, and Launch Services operations.
@MainActor
final class ApplicationService: ApplicationServicing {
    private let workspace: NSWorkspace
    private var iconCache: [URL: NSImage] = [:]

    /// Uses the supplied workspace; constructing the service does not enumerate or launch apps.
    init(workspace: NSWorkspace = .shared) { self.workspace = workspace }

    /// Returns regular, bundle-backed apps, excluding DeeDock and background/accessory processes.
    func runningApplications() -> [ApplicationReference] {
        workspace.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let url = app.bundleURL else { return nil }
            return ApplicationReference(bundleIdentifier: app.bundleIdentifier, url: url,
                                        name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Resolves the initial pin choices, skipping apps that are not installed.
    func defaultFavorites() -> [ApplicationReference] {
        ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.systempreferences"]
            .compactMap { identifier in
                guard let url = workspace.urlForApplication(withBundleIdentifier: identifier) else { return nil }
                return ApplicationReference(bundleIdentifier: identifier, url: url,
                                            name: FileManager.default.displayName(atPath: url.path)
                                                .replacingOccurrences(of: ".app", with: ""))
            }
    }

    /// Uses the saved location when present, then resolves moved apps by bundle identifier.
    func resolvedURL(for reference: ApplicationReference) -> URL? {
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime(access) {} }
        if FileManager.default.fileExists(atPath: access.url.path) { return access.url }
        return reference.bundleIdentifier.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Returns a cached icon, loading it once per resolved URL, or an unavailable-app symbol.
    func icon(for url: URL?) -> NSImage {
        guard let url else { return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil)! }
        if let image = iconCache[url] { return image }
        let image = workspace.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        iconCache[url] = image
        return image
    }

    /// Releases icons no longer referenced by any active dock snapshot.
    func pruneIcons(keeping urls: Set<URL>) { iconCache = iconCache.filter { urls.contains($0.key) } }

    /// Opens or activates the referenced app without requesting a new process instance.
    /// - Throws: A missing-bundle error or the failure reported by Launch Services.
    /// - Note: Cancellation cannot undo a launch already submitted to macOS.
    func open(_ reference: ApplicationReference) async throws {
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime(access) {} }
        guard let url = resolvedURL(for: reference) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: String(localized: .errorAppNotFound(appName: reference.name))])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }
}
