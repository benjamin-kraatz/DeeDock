import ExtensionFoundation

extension AppExtensionPoint {
    /// DOKK's plugin extension point, the same identifier in DOKK and DOKK Dev.
    ///
    /// Declared by `Configuration/DOKKPluginExtensionPoint.appexpt`, a static ExtensionKit plist the
    /// "Embed Extension Point" build phase copies into `Contents/Extensions`, rather than by
    /// `@AppExtensionPoint.Definition`. The Swift definition always names the point
    /// `<bundle identifier>.<name>`, which gives DOKK and DOKK Dev two separate points, so a plugin
    /// built against one never loads in the other.
    ///
    /// LaunchServices registers a third-party point only when its identifier starts with the
    /// declaring app's bundle identifier. `de.benjaminkraatz.DeeDock.dev.plugin` starts with both the
    /// Debug (`de.benjaminkraatz.DeeDock.dev`) and the Release (`de.benjaminkraatz.DeeDock`) identifier,
    /// so both builds can declare it. The identifier must be a literal; keep it in step with
    /// ``DOKKPluginContract/extensionPointIdentifier`` and the plist.
    /// - Throws: ``AppExtensionPoint/Error/hostMustDefineAppExtensionPoint(_:)`` when the running
    ///   bundle does not carry the declaration, such as in a SwiftUI preview.
    static func dokkPlugin() throws -> AppExtensionPoint {
        try AppExtensionPoint(identifier: "de.benjaminkraatz.DeeDock.dev.plugin")
    }
}
