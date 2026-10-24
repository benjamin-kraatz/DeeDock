import AppKit

/// Everything an ``AppUninstallSession`` does to the system, injected so previews and tests never touch
/// real files or processes.
///
/// The `@Sendable` synchronous members do file-system work; the session calls them from detached tasks,
/// never on the main actor. The `@MainActor` members drive AppKit.
struct AppUninstallServices {
    var inspect: @Sendable (URL, String) -> AppUninstallTarget
    var scan: @Sendable (AppUninstallTarget) -> [AppLeftover]
    var measure: @Sendable (URL) -> AppLeftoverMeasure
    var needsFinder: @Sendable (URL) -> Bool
    var exists: @Sendable (URL) -> Bool
    var finderTrash: @Sendable ([URL]) async -> AppUninstallFinder.Outcome
    var isRunning: @MainActor (URL) -> Bool
    var quit: @MainActor (URL) async -> Bool
    var recycle: @MainActor (URL) async -> AppUninstallWorkspace.RecycleResult
    var openAccessSettings: @MainActor () -> Void
    var relaunch: @MainActor (URL) -> Bool

    /// The real services.
    /// - Parameter installed: The installed apps as the Launcher lists them, for skipping data they own or
    ///   share. Their app groups are read only when the uninstalled app declares groups of its own. The
    ///   Launcher keeps one copy per bundle identifier, so other copies of the app itself are looked up
    ///   separately.
    static func live(installed: [ApplicationReference]) -> AppUninstallServices {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppUninstallServices(
            inspect: { url, name in AppUninstallInspector.inspect(url, name: name) },
            scan: { target in
                let path = target.url.standardizedFileURL.path
                let groups = { (url: URL) in
                    target.appGroups.isEmpty ? [] : AppUninstallInspector.appGroups(of: url, team: target.teamIdentifier)
                }
                // Vendors share privileged helpers between products (one updater for a whole suite), so another
                // app declaring one of this app's helpers keeps it unselected.
                let helpers = { (url: URL) in
                    target.helperIdentifiers.isEmpty ? [] : AppUninstallInspector.helperIdentifiers(of: url)
                }
                var others = installed.filter {
                    $0.url.standardizedFileURL.path != path && $0.bundleIdentifier != target.bundleIdentifier
                }.map {
                    AppLeftoverRules.OtherApp(bundleIdentifier: $0.bundleIdentifier, name: $0.name, appGroups: groups($0.url),
                                              otherIdentifiers: helpers($0.url))
                }
                // Another copy of this app shares its data, including its extensions' and helpers', which then
                // starts unselected ("Also used by …").
                if let identifier = target.bundleIdentifier {
                    for copy in AppUninstallInspector.otherCopies(of: identifier, excluding: target.url, home: home) {
                        let folder = copy.deletingLastPathComponent().path
                        let shown = folder.hasPrefix(home.path + "/") ? "~" + folder.dropFirst(home.path.count) : folder
                        let inspected = AppUninstallInspector.inspect(copy, name: target.name)
                        others.append(AppLeftoverRules.OtherApp(
                            bundleIdentifier: identifier, name: "\(target.name) (\(shown))", appGroups: inspected.appGroups,
                            otherIdentifiers: inspected.embeddedIdentifiers + inspected.helperIdentifiers))
                    }
                }
                return AppLeftoverScanner.scan(target, others: others, home: home)
            },
            measure: AppLeftoverScanner.measure,
            needsFinder: AppUninstallWorkspace.needsFinder,
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            finderTrash: { await AppUninstallFinder.moveToTrash($0) },
            isRunning: { !AppUninstallWorkspace.runningApplications(of: $0).isEmpty },
            quit: { await AppUninstallWorkspace.quit($0) },
            recycle: { await AppUninstallWorkspace.recycle($0) },
            openAccessSettings: {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                NSWorkspace.shared.open(url)
            },
            relaunch: { AppUninstallRelaunch.relaunch(reopening: $0) })
    }

    /// Services that do nothing, for previews: no app is running and nothing moves.
    static let inert = AppUninstallServices(
        inspect: { url, name in
            AppUninstallTarget(url: url, name: name, bundleIdentifier: nil, version: nil, source: .downloaded,
                               ownedByRoot: false, teamIdentifier: nil, appGroups: [], embeddedIdentifiers: [],
                               helperIdentifiers: [], names: [name], hasSystemExtensions: false, vendorUninstaller: nil,
                               byteCount: nil)
        },
        scan: { _ in [] }, measure: { _ in .size(0) }, needsFinder: { _ in false }, exists: { _ in true },
        finderTrash: { _ in .cancelled }, isRunning: { _ in false }, quit: { _ in true }, recycle: { _ in .failed },
        openAccessSettings: {}, relaunch: { _ in false })
}
