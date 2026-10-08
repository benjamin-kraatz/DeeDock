import Foundation

/// Resolves a one-line "what this app does" description for Robi, trying sources in a fixed order:
///
/// 1. Bundled Homebrew cask descriptions (`HomebrewAppDescriptions.json`, by bundle identifier, then app name).
/// 2. The App Store, through `LauncherAppStoreLookup`, for Mac App Store installs only.
/// 3. The bundled hand-maintained list (`CuratedAppDescriptions.json`).
///
/// The first source with an entry wins. Document-type capabilities are separate and always included
/// (see `LauncherAppCapabilities`). Bundled catalogs load lazily on the first Robi request and stay in memory.
actor LauncherAppDescriptions {
    private nonisolated struct Catalog: Decodable {
        var bundleIdentifiers: [String: String] = [:]
        var appNames: [String: String]? = nil
    }

    private let appStore: LauncherAppStoreLookup
    private var homebrew: Catalog?
    private var curated: Catalog?

    init(appStore: LauncherAppStoreLookup = LauncherAppStoreLookup()) {
        self.appStore = appStore
    }

    /// Returns descriptions keyed by `LauncherApplication.id`. Apps without a description are absent.
    ///
    /// May make one network request per 50 uncached App Store apps; never throws, and returns local results
    /// when offline or cancelled.
    func descriptions(for applications: [LauncherApplication]) async -> [String: String] {
        let homebrew = loadHomebrew()
        var result: [String: String] = [:]
        var appStoreCandidates: [LauncherApplication] = []
        for application in applications {
            let appName = application.reference.url.deletingPathExtension().lastPathComponent.lowercased()
            if let identifier = application.reference.bundleIdentifier, let description = homebrew.bundleIdentifiers[identifier] {
                result[application.id] = description
            } else if let description = homebrew.appNames?[appName] {
                result[application.id] = description
            } else if application.reference.bundleIdentifier != nil, Self.isAppStoreInstall(application.reference.url) {
                appStoreCandidates.append(application)
            }
        }
        let storeDescriptions = await appStore.descriptions(for: appStoreCandidates.compactMap(\.reference.bundleIdentifier))
        let curated = loadCurated()
        for application in applications where result[application.id] == nil {
            guard let identifier = application.reference.bundleIdentifier else { continue }
            if let description = storeDescriptions[identifier] ?? curated.bundleIdentifiers[identifier] {
                result[application.id] = description
            }
        }
        return result
    }

    /// The App Store writes a receipt into every app it installs; other apps are never sent to Apple.
    nonisolated static func isAppStoreInstall(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
    }

    private func loadHomebrew() -> Catalog {
        if let homebrew { return homebrew }
        let catalog = Self.loadCatalog("HomebrewAppDescriptions")
        homebrew = catalog
        return catalog
    }

    private func loadCurated() -> Catalog {
        if let curated { return curated }
        let catalog = Self.loadCatalog("CuratedAppDescriptions")
        curated = catalog
        return catalog
    }

    /// Every bundle identifier in the bundled Homebrew and curated catalogs. Reads both files on
    /// each call, so callers keep the result instead of asking again.
    nonisolated static func bundledBundleIdentifiers() -> Set<String> {
        Set(loadCatalog("HomebrewAppDescriptions").bundleIdentifiers.keys)
            .union(loadCatalog("CuratedAppDescriptions").bundleIdentifiers.keys)
    }

    private nonisolated static func loadCatalog(_ name: String) -> Catalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return Catalog() }
        return catalog
    }
}
