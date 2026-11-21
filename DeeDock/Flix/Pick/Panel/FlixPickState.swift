import AppKit
import Observation

/// What Flix Pick's panel shows, and the actions its rows send back. Main actor.
///
/// `FlixPickCoordinator` fills it for each picker; the views read it and call the closures, never
/// the coordinator. Hover opens the Tuck rail (``isOpen``) and only highlights: nothing takes
/// focus from the app whose picker is in front.
@MainActor @Observable
final class FlixPickState {
    var kind: FlixPickPickerKind = .open
    /// Supplied by macOS; never translated.
    var appName = ""
    /// The picker's default button ("Open", "Import"), for the subtitle.
    var buttonTitle: String?
    var rows: [FlixPickRow] = []
    /// The rail is open to its full width (hovered).
    var isOpen = false
    /// The panel is on screen (drives its entrance).
    var isShown = false
    var side: FlixPickPlacement.Side = .right
    /// The row whose action is running.
    var busyRowID: FlixItem.ID?
    /// A short note in the footer after an action could not reach the picker.
    var message: String?
    var now = Date.now
    var policy = FlixReadPolicy(allowedRoots: [])
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false

    /// A row was clicked, ⌥-clicked, double-clicked, or used through VoiceOver; `confirm` also
    /// presses the picker's default button.
    @ObservationIgnored var activate: ((_ row: FlixPickRow, _ trigger: FlixPickTrigger, _ confirm: Bool) -> Void)?
    /// A drag started on a row.
    @ObservationIgnored var beginDrag: ((FlixPickRow, NSView, NSEvent) -> Void)?
    /// The pointer entered or left the panel body.
    @ObservationIgnored var hoverChanged: ((Bool) -> Void)?
    /// The ⋯ menu's **Not in <App>**.
    @ObservationIgnored var disableForApp: (() -> Void)?
    /// The ⋯ menu's **Flix Pick Settings…**, before Settings opens.
    @ObservationIgnored var prepareSettings: (() -> Void)?
    /// The ⋯ menu opened or closed; the rail stays open while it tracks.
    @ObservationIgnored var menuTracking: ((Bool) -> Void)?

    init() {}

    /// Reads Reduce Motion, Reduce Transparency, and Increase Contrast, before each picker.
    func refreshAccessibilityOptions() {
        let workspace = NSWorkspace.shared
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
    }
}
