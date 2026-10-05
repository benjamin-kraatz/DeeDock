import Foundation

// Closed vocabularies for app-level events: Settings navigation, permissions, the login item,
// displays, and the app tile's context menu. Every value is a compile-time constant.

/// A Settings sidebar section. Displays are reported by role, never by name or identifier.
nonisolated enum AnalyticsSettingsSection: String, AnalyticsToken {
    case general, dock, atmosphere, modes, extras, windowsFocus = "windows_focus"
    case suggestionsHistory = "suggestions_history", deprecated, display

    init(_ section: SettingsSection) {
        switch section {
        case .general: self = .general
        case .dock: self = .dock
        case .atmosphere: self = .atmosphere
        case .modes: self = .modes
        case .extras: self = .extras
        case .windowsFocus: self = .windowsFocus
        case .suggestionsHistory: self = .suggestionsHistory
        case .deprecated: self = .deprecated
        case .display: self = .display
        }
    }
}

/// How a Settings section or page came on screen.
nonisolated enum AnalyticsSettingsNavigation: String, AnalyticsToken {
    /// The sidebar, including a sidebar search result.
    case sidebar
    /// A page link in a section's overview.
    case overview
    /// A menu, dock tile, or other DOKK feature asked for this destination.
    case request
}

/// A macOS privacy permission DOKK depends on.
nonisolated enum AnalyticsPermission: String, AnalyticsToken {
    case accessibility, screenRecording = "screen_recording"
}

nonisolated enum AnalyticsPermissionStatus: String, AnalyticsToken {
    case enabled, notEnabled = "not_enabled", unavailable

    init(_ status: WindowAccessStatus) {
        switch status {
        case .enabled: self = .enabled
        case .notEnabled: self = .notEnabled
        case .unavailable: self = .unavailable
        }
    }

    init(_ status: ScreenCaptureAccessStatus) {
        switch status {
        case .enabled: self = .enabled
        case .notEnabled: self = .notEnabled
        case .unavailable: self = .unavailable
        }
    }
}

/// What a person asked of the login item.
nonisolated enum AnalyticsLoginItemOperation: String, AnalyticsToken {
    case register, unregister, cancelRequest = "cancel_request"

    init(_ operation: LoginItemController.Operation) {
        switch operation {
        case .register: self = .register
        case .unregister: self = .unregister
        case .cancelRequest: self = .cancelRequest
        }
    }
}

/// An item chosen from an app tile's context menu. Pin, Badge Memory, and App Melt items report
/// through their own events.
nonisolated enum AnalyticsAppMenuAction: String, AnalyticsToken {
    case showInFinder = "show_in_finder", hide, show, bringAllToFront = "bring_all_to_front", quit
    case selectWindow = "select_window"

    init(_ action: ApplicationMenuAction) {
        switch action {
        case .showInFinder: self = .showInFinder
        case .setHidden(let hidden): self = hidden ? .hide : .show
        case .bringAllToFront: self = .bringAllToFront
        case .quit: self = .quit
        case .selectWindow: self = .selectWindow
        }
    }
}

/// How documents reached an app tile.
nonisolated enum AnalyticsDocumentSource: String, AnalyticsToken {
    /// Files dropped on the tile.
    case drop
    /// The tile's Open Files… picker.
    case picker
}
