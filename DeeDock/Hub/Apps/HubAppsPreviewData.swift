#if DEBUG
import AppKit

/// Canvas fixtures for the Apps tab. They never start workspace observation, discovery, window
/// search, predictions, real preferences, or app launches. Icons are read from the system apps'
/// bundles when present, which only reads files.
@MainActor
enum HubAppsPreviewData {
    static let names = [
        "Calendar", "Notes", "Music", "Safari", "Terminal", "Xcode", "Mail", "Maps", "Photos",
        "Preview", "Reminders", "System Settings", "Atlas", "An Application With a Particularly Long Name",
    ]

    /// A model whose launcher shows `names` as discovered apps.
    /// - Parameters:
    ///   - suggested: Installs a three-app suggestion snapshot (Xcode, Notes, Music).
    ///   - list: Uses the list layout instead of the grid.
    ///   - lineIcons: Draws line glyphs for apps the bundled catalog covers.
    ///   - query: Starts with this query, which switches to mixed search.
    ///   - names: Overrides the discovered apps (default ``names``); pass `[]` for an empty library.
    static func model(suggested: Bool = false, list: Bool = false, lineIcons: Bool = false,
                      query: String = "", names: [String]? = nil) -> HubAppsModel {
        let applications = (names ?? Self.names).enumerated().map { index, name in
            LauncherApplication(
                reference: ApplicationReference(bundleIdentifier: "preview.hub.\(index)",
                                                url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name),
                category: index.isMultiple(of: 2) ? "public.app-category.productivity"
                                                  : "public.app-category.utilities")
        }
        let service = HubAppsPreviewService(running: applications.prefix(3).map(\.reference))
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        if suggested { store.setEnabled(true) }
        let history = LauncherHistory(defaults: nil)
        let catalog = ApplicationCatalog(service: service, launcherHistory: history,
                                         launcherLibrary: LauncherLibrary(applications: applications),
                                         suggestions: store)
        catalog.refresh()
        let launcher = LauncherState(catalog: catalog) { application in
            HubAppsPreviewData.icon(named: application.reference.name)
        }
        launcher.layout = list ? .list : .grid
        launcher.usesLineIcons = lineIcons
        launcher.activateForPreview()
        if suggested, applications.count >= 6 {
            let picks = [applications[5], applications[1], applications[2]]
            history.record(picks[1].reference)
            let date = Date()
            launcher.suggestions.installPreview(LauncherSuggestionSnapshot(
                context: LauncherSuggestionContext(date: date, foregroundID: "preview.source", modeID: nil),
                modelVersion: "preview", rankedIDs: picks.map(\.id), createdAt: date,
                generation: store.revision))
        }
        launcher.query = query
        return HubAppsModel(launcher: launcher)
    }

    /// The model with a two-file batch in file-action mode.
    static func fileActionsModel() -> HubAppsModel {
        let model = model()
        model.adoptFiles(.owned(
            DocumentResourceAccess([URL(fileURLWithPath: "/Preview/Quarterly report.pdf"),
                                    URL(fileURLWithPath: "/Preview/Missing.txt")],
                                   startAccess: { _ in false }, stopAccess: { _ in }),
            source: .shelf))
        return model
    }

    static func icon(named name: String) -> NSImage {
        let path = ["/System/Applications/\(name).app", "/System/Applications/Utilities/\(name).app",
                    "/Applications/\(name).app"].first { FileManager.default.fileExists(atPath: $0) }
        if let path { return NSWorkspace.shared.icon(forFile: path) }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 64, height: 64))
    }
}

/// Reports fixed running apps and never opens anything.
@MainActor
private final class HubAppsPreviewService: ApplicationServicing {
    let running: [ApplicationReference]
    init(running: [ApplicationReference]) { self.running = running }
    func runningApplications() -> [ApplicationReference] { running }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { HubAppsPreviewData.icon(named: url?.deletingPathExtension().lastPathComponent ?? "") }
    func pruneIcons(keeping urls: Set<URL>) {}
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome { .opened }
    func open(_ reference: ApplicationReference) async throws {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws {}
}
#endif
