import AppKit
import SwiftUI

extension AppLeftover.Kind {
    /// The row title in the uninstall sheet.
    var title: LocalizedStringResource {
        switch self {
        case .container: .hubUninstallKindContainer
        case .extensionContainer: .hubUninstallKindExtensionContainer
        case .groupContainer: .hubUninstallKindGroupContainer
        case .scripts: .hubUninstallKindScripts
        case .applicationSupport: .hubUninstallKindApplicationSupport
        case .caches: .hubUninstallKindCaches
        case .preferences: .hubUninstallKindPreferences
        case .savedState: .hubUninstallKindSavedState
        case .webData: .hubUninstallKindWebData
        case .logs: .hubUninstallKindLogs
        case .launchAgent: .hubUninstallKindLaunchAgent
        case .backgroundHelper: .hubUninstallKindBackgroundHelper
        case .folder: .hubUninstallKindFolder
        case .homeFolder: .hubUninstallKindHomeFolder
        }
    }

    /// The SF Symbol in the row's icon tile.
    var symbol: String {
        switch self {
        case .container: "shippingbox"
        case .extensionContainer: "puzzlepiece.extension"
        case .groupContainer: "person.2"
        case .scripts: "applescript"
        case .applicationSupport, .folder: "folder"
        case .caches: "bolt"
        case .preferences: "gearshape"
        case .savedState: "macwindow"
        case .webData: "globe"
        case .logs: "doc.text"
        case .launchAgent: "power"
        case .backgroundHelper: "gearshape.2"
        case .homeFolder: "house"
        }
    }
}

extension AppUninstallSource {
    /// The badge next to the version.
    var badge: LocalizedStringResource {
        switch self {
        case .appStore: .hubUninstallSourceAppStore
        case .testFlight: .hubUninstallSourceTestFlight
        case .installer: .hubUninstallSourceInstaller
        case .downloaded: .hubUninstallSourceDownloaded
        }
    }

    /// The bold start of the password note for a root-owned app from this source.
    var passwordTitle: LocalizedStringResource {
        switch self {
        case .appStore: .hubUninstallPasswordAppStore
        case .testFlight: .hubUninstallPasswordTestFlight
        case .installer, .downloaded: .hubUninstallPasswordInstaller
        }
    }
}

/// Formatting shared by the uninstall sheet's views.
enum AppUninstallFormat {
    /// A file size the way Finder shows it, such as “31.4 MB”.
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    /// `url`'s path with the home folder shortened to `~`.
    static func path(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// The size cell's text for a measure.
    static func size(_ measure: AppLeftoverMeasure?) -> Text {
        switch measure {
        case .size(let count): Text(verbatim: Self.bytes(count))
        case .unreadable: Text(.hubUninstallUnreadable)
        case .measuring, nil: Text(.hubUninstallCalculating)
        }
    }
}

/// The app's icon from macOS, or a placeholder when the bundle is gone.
struct HubUninstallAppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: url.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
