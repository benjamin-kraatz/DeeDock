import AppKit

/// Outcome of asking `NSWorkspace` to open a System Settings URL.
enum SystemSettingsDeepLinkOpenResult: Equatable, Sendable {
    /// The requested pane URL was accepted.
    case opened
    /// The pane URL failed, and System Settings opened at its root instead.
    case openedRoot
    /// Neither the pane nor System Settings could be opened.
    case failed
}

/// Opens `x-apple.systempreferences:` URLs and falls back without crashing.
///
/// This type never writes preferences, runs AppleScript against System Settings, or
/// requests TCC. It only asks the workspace to open a URL.
enum SystemSettingsDeepLinkOpener {
    /// Legacy root that still launches System Settings when a pane ID is unknown.
    static let rootURL = URL(string: "x-apple.systempreferences:com.apple.preferences")

    /// Bundle ID of the System Settings app on current macOS.
    static let settingsBundleIdentifier = "com.apple.systempreferences"

    /// Opens `pane`, then the System Settings root, then the Settings app itself.
    @discardableResult
    static func open(_ pane: SystemSettingsClonePane) -> SystemSettingsDeepLinkOpenResult {
        let workspace = NSWorkspace.shared
        if let url = pane.url, workspace.open(url) {
            return .opened
        }
        return openRoot(using: workspace)
    }

    /// Opens System Settings without targeting a pane.
    @discardableResult
    static func openRoot(using workspace: NSWorkspace = .shared) -> SystemSettingsDeepLinkOpenResult {
        if let rootURL, workspace.open(rootURL) {
            return .openedRoot
        }
        if let settings = workspace.urlForApplication(withBundleIdentifier: settingsBundleIdentifier) {
            workspace.open(settings)
            return .openedRoot
        }
        return .failed
    }
}
