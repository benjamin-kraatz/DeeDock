// DOKK Sample Plugin: a developer example, never shipped with DOKK. See docs/PLUGINS.md.

import ExtensionFoundation
import ExtensionKit
import SwiftUI

/// Binds to DOKK's plugin extension point and provides the panel scene plus DOKK's background
/// connection.
///
/// The identifier is the one fixed point DOKK and DOKK Dev both declare,
/// `de.benjaminkraatz.DeeDock.dev.plugin` (``DOKKPluginContract/extensionPointIdentifier``), so this
/// plugin loads in either. Spell it as `host` plus `name`, in literals: the build reads them to
/// write the extension's Info.plist, and it skips the single-string `Identifier(_:)` form.
@main
struct SamplePluginExtension: AppExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "de.benjaminkraatz.DeeDock.dev", name: "plugin")
    }

    /// DOKK's background connection arrives through the `ConnectionHandler`, the scene's through
    /// `onConnection`. Both go to the same link, so they share one tile state.
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            SamplePluginPanelScene(),
            configuration: ConnectionHandler(onConnection: { SamplePluginModel.accept($0) })
        )
    }
}

/// The panel DOKK hosts above the plugin's tile. Its ID is ``DOKKPluginContract/panelSceneID``.
struct SamplePluginPanelScene: AppExtensionScene {
    var body: some AppExtensionScene {
        PrimitiveAppExtensionScene(id: DOKKPluginContract.panelSceneID) {
            SamplePluginPanelView(model: .shared)
        } onConnection: { SamplePluginModel.accept($0) }
    }
}
