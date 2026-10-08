import Foundation

/// The bundle identifier of a publicly distributed app, which may leave the Mac in
/// ``AnalyticsEvent/lineIconCoverage(_:)``.
///
/// This is the only exception to the rule that analytics never identifies an app, and it exists
/// so we know which Line glyphs to draw next. Only ``AnalyticsPublicApps`` can create a value, and
/// only for an app anyone can get. An in-house build or a company's internal tool never qualifies,
/// so it is only ever counted.
nonisolated struct AnalyticsPublicAppIdentifier: Hashable, Comparable, Sendable {
    let bundleIdentifier: String

    fileprivate init(_ bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.bundleIdentifier < rhs.bundleIdentifier }
}

/// Decides whether an app is publicly distributed, from evidence already on the Mac.
///
/// An app qualifies when Apple ships it inside macOS, when the bundled Homebrew or curated
/// description catalogs list its bundle identifier, or when it carries a Mac App Store receipt.
/// Nothing is looked up online.
nonisolated struct AnalyticsPublicApps: Sendable {
    /// Bundle identifiers from the bundled Homebrew and curated description catalogs.
    let catalogedIdentifiers: Set<String>
    /// Whether the bundle at a URL was installed by the Mac App Store.
    let isAppStoreInstall: @Sendable (URL) -> Bool

    init(catalogedIdentifiers: Set<String>, isAppStoreInstall: @escaping @Sendable (URL) -> Bool) {
        self.catalogedIdentifiers = catalogedIdentifiers
        self.isAppStoreInstall = isAppStoreInstall
    }

    /// Reads the catalogs shipped in the app bundle. Call off the main actor: the Homebrew
    /// catalog is about 300 KB of JSON.
    static func bundled() -> AnalyticsPublicApps {
        AnalyticsPublicApps(catalogedIdentifiers: LauncherAppDescriptions.bundledBundleIdentifiers(),
                            isAppStoreInstall: LauncherAppDescriptions.isAppStoreInstall)
    }

    /// The identifier that may be reported for `application`, or nil when it is not public.
    func identifier(for application: ApplicationReference) -> AnalyticsPublicAppIdentifier? {
        guard let identifier = application.bundleIdentifier, !identifier.isEmpty else { return nil }
        // Apple's own apps live on the sealed system volume; a `com.apple.` identifier elsewhere
        // could be anyone's build.
        let isSystemApp = identifier.hasPrefix("com.apple.") && application.url.path.hasPrefix("/System/")
        guard isSystemApp || catalogedIdentifiers.contains(identifier) || isAppStoreInstall(application.url)
        else { return nil }
        return AnalyticsPublicAppIdentifier(identifier)
    }
}
