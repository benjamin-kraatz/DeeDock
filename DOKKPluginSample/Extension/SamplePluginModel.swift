// DOKK Sample Plugin: a developer example, never shipped with DOKK. See docs/PLUGINS.md.

import Foundation
import Observation

/// The sample's state: one badge number, kept in memory, so a restarted plugin starts again at 0.
///
/// A real plugin would persist what its tile shows or derive it again when its process starts.
@MainActor @Observable
final class SamplePluginModel {
    static let shared = SamplePluginModel()

    private static let resetItem = "reset-badge"
    private static let openAppItem = "open-app"
    private static let bumpInPanelItem = "bump-in-panel"

    private(set) var badge = 0
    /// Whether DOKK's panel is showing this plugin's scene right now.
    private(set) var panelOpen = false
    let link: DOKKPluginHostLink

    private init() {
        link = DOKKPluginHostLink(tileState: Self.tileState(badge: 0))
        link.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Accepts a connection from DOKK. ExtensionKit calls this off the main thread, so the link,
    /// which lives on the main actor, configures and resumes the connection there.
    nonisolated static func accept(_ connection: NSXPCConnection) -> Bool {
        nonisolated(unsafe) let connection = connection
        Task { @MainActor in _ = shared.link.accept(connection) }
        return true
    }

    func bumpBadge() { setBadge(badge + 1) }
    func resetBadge() { setBadge(0) }

    /// Asks DOKK to close the panel and open this sample's app.
    func openApp() { link.request(.openApp) }

    /// Ends the process abruptly, to show that DOKK keeps running and offers Restart.
    func crash() -> Never {
        fatalError("DOKK Sample Plugin: intentional crash to show DOKK's stopped state")
    }

    private func setBadge(_ value: Int) {
        badge = max(0, value)
        link.tileState = Self.tileState(badge: badge)
    }

    private func handle(_ event: DOKKPluginHostEvent) {
        switch event {
        case .panelOpened: panelOpen = true
        case .panelClosed, .willDisconnect: panelOpen = false
        case .menuItemChosen(Self.resetItem): resetBadge()
        case .menuItemChosen(Self.openAppItem): openApp()
        case .menuItemChosen(Self.bumpInPanelItem): bumpBadge()
        case .menuItemChosen: break
        }
    }

    /// Everything the tile needs, in one value. The panel asks for 320 × 226 points of content.
    private static func tileState(badge: Int) -> DOKKPluginTileState {
        DOKKPluginTileState(
            title: "Sample Plugin",
            badge: badge > 0 ? .count(badge) : nil,
            accessibilityValue: badge > 0 ? "Badge \(badge)" : nil,
            panelSize: DOKKPluginSize(width: 320, height: 226),
            primaryAction: .openPanel,
            menuItems: [
                DOKKPluginMenuItem(id: resetItem, title: "Reset Badge", systemImage: "arrow.counterclockwise"),
                DOKKPluginMenuItem(id: openAppItem, title: "Show Sample App", systemImage: "macwindow"),
                // Opens the panel first, so the bump is visible as it happens.
                DOKKPluginMenuItem(id: bumpInPanelItem, title: "Bump Badge in Panel", systemImage: "plus.circle",
                                   opensPanel: true),
            ])
    }
}
