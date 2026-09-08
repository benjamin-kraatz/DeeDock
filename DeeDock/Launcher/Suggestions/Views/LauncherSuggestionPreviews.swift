#if DEBUG
import SwiftUI

/// Canvas fixtures never start workspace observation, discovery, real preferences, or app launches.
@MainActor
private enum LauncherSuggestionPreviewData {
    static func state(list: Bool = false, learned: Bool = true) -> LauncherState {
        let names = ["Notes", "Calendar", "An Application With a Particularly Long Name", "Notes", "Terminal", "Music"]
        let applications = names.enumerated().map { index, name in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "preview.suggestions.\(index)",
                url: URL(fileURLWithPath: "/Preview/Suggestions/\(index).app"), name: name),
                category: "public.app-category.productivity")
        }
        let service = LauncherSuggestionPreviewService(running: [applications[0].reference])
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        store.setEnabled(true)
        let catalog = ApplicationCatalog(service: service, launcherHistory: LauncherHistory(defaults: nil),
            launcherLibrary: LauncherLibrary(applications: applications), suggestions: store)
        catalog.refresh()
        let state = LauncherState(catalog: catalog, iconProvider: { _ in service.icon(for: nil) })
        state.layout = list ? .list : .grid
        state.navigationColumns = list ? 1 : 5
        state.isPresented = true; state.contentVisible = true
        let date = Date()
        let snapshot = LauncherSuggestionSnapshot(
            context: LauncherSuggestionContext(date: date, foregroundID: "preview.source", modeID: nil),
            modelVersion: "preview", rankedIDs: learned ? Array(applications.prefix(3).map(\.id)) : [],
            createdAt: date, generation: store.revision)
        state.suggestions.installPreview(snapshot)
        if learned { state.selectedID = .suggested(applications[0].id) }
        return state
    }
}

@MainActor
private final class LauncherSuggestionPreviewService: ApplicationServicing {
    let running: [ApplicationReference]
    init(running: [ApplicationReference]) { self.running = running }
    func runningApplications() -> [ApplicationReference] { running }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage {
        NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 64, height: 64))
    }
    func pruneIcons(keeping urls: Set<URL>) {}
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome { .opened }
    func open(_ reference: ApplicationReference) async throws {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws {}
}

#Preview("Suggested row: running, closed, and duplicate ordinary apps") {
    LauncherView(state: LauncherSuggestionPreviewData.state())
        .frame(width: 900, height: 680)
        .allowsHitTesting(false)
}

#Preview("Suggested list: German, dark, long names") {
    LauncherView(state: LauncherSuggestionPreviewData.state(list: true))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 760)
        .allowsHitTesting(false)
}

#Preview("Suggestions enabled without learned examples") {
    LauncherView(state: LauncherSuggestionPreviewData.state(learned: false))
        .frame(width: 900, height: 680)
        .allowsHitTesting(false)
}
#endif
