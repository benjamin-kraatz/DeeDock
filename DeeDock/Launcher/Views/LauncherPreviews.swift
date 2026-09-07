#if DEBUG
import SwiftUI

/// Deterministic metadata and symbol artwork. No discovery, launches, or real preferences are used.
private enum LauncherPreviewData {
    static func state(
        list: Bool = false,
        empty: Bool = false,
        grouping: LauncherGrouping = .none
    )
        -> LauncherState
    {
        let names = [
            "Atlas", "Calendar", "Code Studio", "Music", "Notes",
            "Photo Library", "Terminal",
            "An Application With a Particularly Long Name",
        ]
        let applications = names.enumerated().map { index, name in
            LauncherApplication(
                reference: ApplicationReference(
                    bundleIdentifier: "preview.\(index)",
                    url: URL(fileURLWithPath: "/Preview/\(index).app"),
                    name: name
                ),
                category: index.isMultiple(of: 2)
                    ? "public.app-category.productivity"
                    : "public.app-category.utilities"
            )
        }
        let catalog = ApplicationCatalog(
            service: ApplicationService(),
            launcherLibrary: LauncherLibrary(applications: applications)
        )
        let state = LauncherState(
            catalog: catalog,
            iconProvider: { _ in
                NSImage(
                    systemSymbolName: "app.fill",
                    accessibilityDescription: nil
                ) ?? NSImage(size: NSSize(width: 64, height: 64))
            }
        )
        state.layout = list ? .list : .grid
        state.grouping = grouping
        state.isPresented = true
        state.contentVisible = true
        if empty { state.query = "No matching app" }
        return state
    }
}

#Preview("Launcher grid") {
    LauncherView(state: LauncherPreviewData.state()).frame(
        width: 900,
        height: 640
    )
}

#Preview("Launcher list, German, dark") {
    LauncherView(state: LauncherPreviewData.state(list: true)).frame(
        width: 720,
        height: 540
    )
    .environment(\.locale, Locale(identifier: "de")).preferredColorScheme(
        .dark
    )
}

#Preview("Launcher list, grouped") {
    let state = LauncherPreviewData.state(
        list: true,
        grouping: .category
    )

    LauncherView(state: state).frame(
        width: 720,
        height: 540
    )
    .environment(\.locale, Locale(identifier: "de")).preferredColorScheme(
        .dark
    )
}

#Preview("Launcher empty search") {
    LauncherView(state: LauncherPreviewData.state(empty: true)).frame(
        width: 720,
        height: 540
    )
}
#endif
