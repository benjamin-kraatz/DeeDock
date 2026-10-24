import Foundation

/// A file or folder an app left outside its bundle, found by ``AppLeftoverScanner``.
nonisolated struct AppLeftover: Identifiable, Sendable, Hashable {
    /// What the item holds; decides its label and symbol in the sheet.
    enum Kind: String, Sendable, CaseIterable {
        case container, extensionContainer, groupContainer, scripts, applicationSupport, caches, preferences,
             savedState, webData, logs, launchAgent, backgroundHelper, folder, homeFolder
    }

    /// Why the scanner thinks the item belongs to the app.
    enum Match: String, Sendable {
        /// Named after the app's bundle identifier, an embedded bundle's, or a helper's.
        case bundleIdentifier
        /// Named after an app group the app declares.
        case appGroup
        /// Named like the app, or a loose identifier match. Listed under "Possibly related", never selected
        /// by DOKK.
        case similarName
    }

    /// Whose data it is.
    enum Domain: String, Sendable {
        /// In the user's `~/Library` or home folder.
        case user
        /// In `/Library`: shared by all users and owned by root, so Finder moves it with the user's password.
        case allUsers
    }

    let url: URL
    let kind: Kind
    let match: Match
    let domain: Domain
    /// macOS privacy protection hides the item from DOKK: another app's container or group container
    /// without Full Disk Access. DOKK can neither measure nor move it.
    var isProtected = false
    /// Another installed app that uses the same data (the same app group or bundle identifier). Such
    /// items start unselected.
    var sharedWith: String?

    var id: String { url.path }

    /// Selected when the sheet opens: the app's own data that no other installed app uses.
    var selectedByDefault: Bool { match != .similarName && sharedWith == nil && !isProtected }

    /// Background helpers and launchd jobs keep running after their files go to the Trash, until the
    /// next restart or log out.
    var keepsRunning: Bool { kind == .launchAgent || kind == .backgroundHelper }
}

/// The measured size of a leftover, filled in after the sheet opens.
nonisolated enum AppLeftoverMeasure: Sendable, Equatable {
    case measuring
    /// Space on disk in bytes of the file, or of everything in the folder.
    case size(Int64)
    /// Only root can read it (some `/Library` items). It can still go to the Trash with the password.
    case unreadable
}
