import AppKit
import ExtensionFoundation
import Observation

/// Where a plugin's process stands, as far as DOKK knows.
enum DockPluginStatus: Equatable {
    /// Not connected, because the plugin has no tile. Its process may still be winding down.
    case idle
    /// DOKK asked for the process and is waiting for its first reply.
    case starting
    /// Connected; the tile shows the plugin's latest state.
    case running
    /// The process exited or never answered. The tile turns grey until the person restarts it.
    case stopped
}

/// One enabled plugin: what the system says about it, what its process last reported, and how
/// DOKK's connection to it stands.
///
/// Shared by every dock, the panel, and Settings. Tiles read the badge from here directly, so a
/// badge change redraws one tile instead of rebuilding every dock.
@MainActor @Observable
final class DockPlugin: Identifiable {
    /// The extension's bundle identifier. Stable across updates; pins are keyed by it.
    let id: String
    /// The system's handle for launching and hosting the plugin. Nil in previews.
    @ObservationIgnored var identity: AppExtensionIdentity?
    /// The extension's display name from its Info.plist.
    private(set) var extensionName: String
    let app: DockPluginApp
    /// The plugin's latest report. Nil until it first answers.
    var tileState: DOKKPluginTileState?
    var status: DockPluginStatus = .idle
    /// Raised by every restart, so an open panel reloads its scene once.
    private(set) var sceneGeneration = 0

    init(id: String, extensionName: String, app: DockPluginApp, identity: AppExtensionIdentity? = nil,
         tileState: DOKKPluginTileState? = nil, status: DockPluginStatus = .idle) {
        self.id = id
        self.extensionName = extensionName
        self.app = app
        self.identity = identity
        self.tileState = tileState
        self.status = status
    }

    /// The name on the tile, in menus, and for VoiceOver. A blank title from the plugin falls back
    /// to the extension's own name.
    var title: String {
        let reported = tileState?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reported.isEmpty ? extensionName : reported
    }

    var isStopped: Bool { status == .stopped }

    /// The app name, shown beside the plugin name only when the two differ.
    var appNameIfDifferent: String? {
        app.name.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ? nil : app.name
    }

    /// The badge as the tile draws it, or nil for none. A stopped plugin's badge is stale and hidden.
    var badge: (label: String, style: DockAppBadge.Style)? {
        guard !isStopped, let badge = tileState?.badge else { return nil }
        switch badge {
        case .count(let count) where count > 0:
            return (count > 99 ? "99+" : count.formatted(), .count)
        case .count:
            return nil
        case .text(let text):
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(DOKKPluginContract.maximumBadgeTextLength))
            return trimmed.isEmpty ? nil : (trimmed, .count)
        case .dot:
            return ("", .dot)
        }
    }

    /// The plugin's own menu commands, capped at the contract's limit.
    var menuItems: [DOKKPluginMenuItem] {
        Array((tileState?.menuItems ?? []).prefix(DOKKPluginContract.maximumMenuItems))
    }

    func noteRestart() { sceneGeneration += 1 }

    /// Takes a tile state from the plugin's session and marks the plugin running.
    /// - Returns: True for the first state of a session, when the plugin was starting or stopped.
    ///   The owner then repeats anything the new process missed, such as an open panel.
    @discardableResult
    func receive(_ state: DOKKPluginTileState) -> Bool {
        let first = status != .running
        tileState = state
        status = .running
        return first
    }

    func update(identity: AppExtensionIdentity) {
        self.identity = identity
        extensionName = identity.localizedName
    }
}

/// The snapshot a dock projects for one pinned plugin.
///
/// Holds only what changes the dock's layout or tooltip. The badge and the restart chip come
/// live from ``DockPlugin``.
struct PluginDockItem: Identifiable, Equatable {
    /// The extension's bundle identifier.
    let pluginID: String
    let title: String
    let icon: NSImage
    let isStopped: Bool
    var id: String { DockEntryID.plugin(pluginID).hitID }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pluginID == rhs.pluginID && lhs.title == rhs.title && lhs.isStopped == rhs.isStopped && lhs.icon === rhs.icon
    }
}
