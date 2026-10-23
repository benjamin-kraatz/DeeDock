import CoreGraphics
import Observation

/// Presentation state for one open plugin panel: its chrome, whether a restart was asked for
/// here, and the commands the coordinator handles.
@MainActor @Observable
final class DockPluginPanelState {
    var chrome = DockPopoverChrome(edge: .bottom, attachment: 190)
    /// Set by the panel's Restart button until the plugin answers, so the stopped view stays up
    /// with a spinner instead of flashing an empty scene.
    var restarting = false
    /// True while the More menu tracks, so its clicks do not count as outside the panel.
    @ObservationIgnored var menuTracking = false

    @ObservationIgnored var restart: (() -> Void)?
    @ObservationIgnored var sceneFailed: (() -> Void)?
    /// The tile menu's actions, for the More button.
    @ObservationIgnored var menuActions: DockPluginMenuActions?
}
