// The DOKK plugin contract, version 1. DOKK and every plugin compile this folder; see docs/PLUGINS.md.
//
// Keep it free of app code: plugin authors copy it into their extension target as is.

import Foundation

/// Identifiers and limits DOKK and a plugin agree on.
///
/// A plugin is an ExtensionKit extension that ships inside its own app. DOKK discovers it on the
/// extension point named here, shows one dock tile for it, and hosts its panel scene in a popover.
/// Everything else travels over XPC as JSON-encoded values from this folder.
nonisolated enum DOKKPluginContract {
    /// The extension point every plugin binds to.
    ///
    /// One fixed identifier serves DOKK and DOKK Dev, so a plugin built against either loads in
    /// both. It carries `.dev` because macOS registers an app's extension point only when the
    /// identifier starts with that app's bundle identifier, and this one has to start with DOKK Dev's
    /// (`de.benjaminkraatz.DeeDock.dev`) as well as DOKK's (`de.benjaminkraatz.DeeDock`).
    ///
    /// A plugin repeats it in its `@AppExtensionPoint.Bind`, as literals split into host and name.
    /// The build turns that into the extension's Info.plist; it writes nothing for the
    /// single-string `Identifier(_:)` form.
    /// ```swift
    /// @AppExtensionPoint.Bind
    /// var boundExtensionPoint: AppExtensionPoint {
    ///     AppExtensionPoint.Identifier(host: "de.benjaminkraatz.DeeDock.dev", name: "plugin")
    /// }
    /// ```
    static let extensionPointIdentifier = "de.benjaminkraatz.DeeDock.dev.plugin"

    /// The `PrimitiveAppExtensionScene` ID of the panel DOKK hosts.
    static let panelSceneID = "dokk-plugin-panel"

    /// The contract version this copy describes.
    ///
    /// Raised only for changes an older peer cannot ignore. Adding an optional field or a new event
    /// kind keeps the version, because both sides skip what they do not know.
    static let version = 1

    /// The most plugin menu items DOKK shows in the tile's menu. Later items are dropped.
    static let maximumMenuItems = 4

    /// The longest badge text DOKK draws. Longer text is cut.
    static let maximumBadgeTextLength = 4
}
