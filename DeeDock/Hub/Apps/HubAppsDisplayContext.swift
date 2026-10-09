import AppKit

/// Per-display inputs for the Apps tab, taken from the dock whose DOKK tile (or Focus Dock, or file
/// drop) opened the Hub.
///
/// The Hub is app-wide, but pins, Pin/Unpin, line-icon appearance, and suggestion visibility still
/// belong to one display's dock. The shell passes a fresh context to
/// ``HubAppsModel/present(on:)`` each time the Hub opens or moves to another display.
struct HubAppsDisplayContext {
    /// Stable display identity (``DockStore/displayID``), never a screen-array index. Scroll
    /// restoration is remembered per display under this key.
    let displayID: String
    /// The source display's pins. Pin/Unpin and "Pin on Display" act on this store.
    weak var dockStore: DockStore?
    /// The source display's Appearance choice for line glyphs in launcher tiles.
    var usesLineIcons: Bool
    /// When line glyphs play their motion on the source display.
    var lineIconMotion: LineIconMotionPlayback
    /// The source display's effective app visibility (the active Dock Mode can hide pinned or
    /// running apps), which suggestions respect.
    var appVisibility: DockAppVisibility
    /// Bundle ID of the app that was frontmost before the Hub took focus. It is the suggestion
    /// context; nil falls back to the current frontmost app when that is not DOKK.
    var foregroundBundleIdentifier: String?

    init(displayID: String, dockStore: DockStore?, usesLineIcons: Bool,
         lineIconMotion: LineIconMotionPlayback, appVisibility: DockAppVisibility,
         foregroundBundleIdentifier: String?) {
        self.displayID = displayID
        self.dockStore = dockStore
        self.usesLineIcons = usesLineIcons
        self.lineIconMotion = lineIconMotion
        self.appVisibility = appVisibility
        self.foregroundBundleIdentifier = foregroundBundleIdentifier
    }
}
