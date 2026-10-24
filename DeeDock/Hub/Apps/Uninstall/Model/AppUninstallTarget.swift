import Foundation

/// Where an app came from, as far as macOS records it. It decides the sheet's badge and whether
/// removing the app needs the user's password.
nonisolated enum AppUninstallSource: String, Sendable {
    /// Carries a Mac App Store receipt (`Contents/_MASReceipt`) of Spotlight type `Production`.
    case appStore
    /// Carries a receipt of Spotlight type `ProductionSandbox`, which TestFlight builds have.
    case testFlight
    /// Owned by root without a store receipt: an installer package put it there for all users.
    case installer
    /// Owned by the user: downloaded, or copied in by hand.
    case downloaded
}

/// What DOKK learned about an app before uninstalling it.
///
/// ``AppUninstallInspector`` builds it off the main actor from the bundle alone (Info.plist, code
/// signature, embedded bundles, Spotlight's receipt and size attributes). Nothing comes from the
/// network.
nonisolated struct AppUninstallTarget: Sendable, Equatable {
    /// The app bundle, standardized.
    let url: URL
    /// The name DOKK shows for the app.
    let name: String
    let bundleIdentifier: String?
    /// `CFBundleShortVersionString`, if the bundle has one.
    let version: String?
    let source: AppUninstallSource
    /// True when root owns the bundle (App Store, TestFlight, and installer-package apps). Only Finder,
    /// with the user's password, can move such a bundle.
    let ownedByRoot: Bool
    let teamIdentifier: String?
    /// App groups the app or its embedded bundles declare in `com.apple.security.application-groups`.
    let appGroups: [String]
    /// Bundle identifiers of embedded extensions, login items, XPC services, and helper apps.
    let embeddedIdentifiers: [String]
    /// Identifiers of privileged helpers and launchd jobs the app declares (`SMPrivilegedExecutables`
    /// and the files in `Contents/Library/LaunchServices`).
    let helperIdentifiers: [String]
    /// Names the app goes by, for the name-only "Possibly related" search.
    let names: [String]
    /// The bundle carries system or network extensions, which moving it to the Trash doesn't reliably remove.
    let hasSystemExtensions: Bool
    /// An uninstaller the vendor ships inside the app or next to it.
    let vendorUninstaller: URL?
    /// The bundle's size on disk from Spotlight, or nil when Spotlight hasn't indexed it.
    let byteCount: Int64?
}
