import SwiftUI

/// What happened to an item most recently, as the activity stream reports it.
///
/// Each item carries only its latest activity: opening a file you downloaded earlier turns its row
/// into an "Opened" row and moves it to the top. The raw values are persisted in the history file,
/// so they must never change.
nonisolated enum FlixActivity: String, Codable, CaseIterable, Sendable {
    /// You opened it (Spotlight's last-used date moved, or an app came to the front).
    case opened
    /// It arrived in a watched folder from the web; `FlixItem.sourcePage` names the page when known.
    case downloaded
    /// It appeared in a watched folder: a screenshot, an export, a new file.
    case created
    /// An existing file in a watched folder was written again.
    case saved
    /// A web page: dropped on Flix Files, or tracked by phase B1's link tracking (off by default).
    case link
    /// You dropped it on the tile or the panel to keep it here.
    case kept

    /// Whether this activity counts toward the tile's "new since you looked" badge.
    ///
    /// Only things that arrived by themselves count. Opening or saving a file is your own doing and
    /// would make the badge meaningless.
    var countsAsNew: Bool {
        switch self {
        case .downloaded, .created: true
        case .opened, .saved, .link, .kept: false
        }
    }

    /// The glyph the event line and the sidebar draw for this activity.
    var symbol: String {
        switch self {
        case .opened: "arrow.up.right"
        case .downloaded: "arrow.down"
        case .created: "plus"
        case .saved: "pencil"
        case .link: "link"
        case .kept: "tray.and.arrow.down"
        }
    }

    /// The event line's colour, matching the mockup: blue opened, green downloaded, orange new,
    /// purple saved.
    var tint: Color {
        switch self {
        case .opened: .accentColor
        case .downloaded: .green
        case .created: .orange
        case .saved: .purple
        case .link: .teal
        case .kept: .indigo
        }
    }
}
