#if DEBUG
import SwiftUI

/// Deterministic apps and symbol artwork. No discovery, launches, or real preferences are used.
@MainActor
private enum CompactLauncherPreviewData {
    static let names = ["Safari", "Mail", "Calendar", "Photos", "Notes", "Reminders",
                        "Music", "Maps", "Messages", "FaceTime", "App Store", "System Settings",
                        "Pages", "Numbers", "Keynote", "Preview", "Terminal", "ChatGPT", "Atlas"]

    /// - Parameter suggested: Installs a fixed three-app ranking in an in-memory suggestion store.
    static func model(lineIcons: Bool = false, query: String = "", suggested: Bool = false) -> CompactLauncherModel {
        let applications = names.enumerated().map { index, name in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "preview.\(index)",
                url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name))
        }
        let store = LauncherSuggestionsStore(directory: nil, defaults: nil)
        store.setEnabled(suggested)
        let catalog = ApplicationCatalog(service: ApplicationService(),
                                         launcherLibrary: LauncherLibrary(applications: applications), suggestions: store)
        let launcher = LauncherState(catalog: catalog) { _ in
            NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 64, height: 64))
        }
        launcher.usesLineIcons = lineIcons
        if suggested {
            // Previews skip `begin`, so the launcher keeps the full style. Six grid columns give it
            // the compact Launcher's limit of three suggestions.
            launcher.navigationColumns = CompactLauncherLayout.columns
            let date = Date()
            launcher.suggestions.installPreview(LauncherSuggestionSnapshot(
                context: LauncherSuggestionContext(date: date, foregroundID: "preview.source", modeID: nil),
                modelVersion: "preview", rankedIDs: [8, 16, 4].map { applications[$0].id },
                createdAt: date, generation: store.revision))
        }
        let model = CompactLauncherModel(launcher: launcher)
        model.query = query
        model.chrome = DockPopoverChrome(edge: .bottom, attachment: 60)
        return model
    }

    static var size: CGSize { CompactLauncherLayout.idealSize }
}

#Preview("Compact Launcher, dark") {
    CompactLauncherView(model: CompactLauncherPreviewData.model())
        .frame(width: CompactLauncherPreviewData.size.width, height: CompactLauncherPreviewData.size.height)
        .padding(24)
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Compact Launcher, suggestions, dark") {
    CompactLauncherView(model: CompactLauncherPreviewData.model(suggested: true))
        .frame(width: CompactLauncherPreviewData.size.width, height: CompactLauncherPreviewData.size.height)
        .padding(24)
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Compact Launcher, suggestions, light") {
    CompactLauncherView(model: CompactLauncherPreviewData.model(suggested: true))
        .frame(width: CompactLauncherPreviewData.size.width, height: CompactLauncherPreviewData.size.height)
        .padding(24)
        .preferredColorScheme(.light)
}

#Preview("Compact Launcher, line icons, German") {
    CompactLauncherView(model: CompactLauncherPreviewData.model(lineIcons: true))
        .frame(width: CompactLauncherPreviewData.size.width, height: CompactLauncherPreviewData.size.height)
        .padding(24)
        .background(.black)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Compact Launcher, light, no matches") {
    CompactLauncherView(model: CompactLauncherPreviewData.model(query: "No matching app"))
        .frame(width: CompactLauncherPreviewData.size.width, height: CompactLauncherPreviewData.size.height)
        .padding(24)
        .preferredColorScheme(.light)
}
#endif
