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

/// Keeps the launcher transition interactive in the canvas without creating a real dock panel.
private struct LauncherTransitionPreview: View {
    private let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    private let closeSpring = Animation.spring(response: 0.28, dampingFraction: 0.86)
    @State private var launcher = LauncherPreviewData.state()

    init() {
        launcher.isPresented = false
        launcher.contentVisible = false
        launcher.expanded = false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if launcher.isPresented {
                LauncherView(state: launcher)
            } else {
                DockPreviewContent(showsLauncher: true, openLauncher: open)
            }
        }
        .frame(width: 900, height: 640)
        .onAppear { launcher.close = close }
        .onDisappear { launcher.close = nil }
    }

    private func open() {
        launcher.dockRect = CGRect(x: 230, y: 526, width: 440, height: 94)
        launcher.contentRect = CGRect(x: 20, y: 20, width: 860, height: 580)
        launcher.isPresented = true
        launcher.contentVisible = false
        launcher.expanded = false
        launcher.close = close
        withAnimation(openSpring) { launcher.expanded = true }
        withAnimation(.smooth(duration: 0.3).delay(0.1)) {
            launcher.contentVisible = true
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.14)) {
            launcher.contentVisible = false
        }
        withAnimation(closeSpring) {
            launcher.expanded = false
        } completion: {
            launcher.isPresented = false
        }
    }
}

#Preview("Launcher grid") {
    LauncherView(state: LauncherPreviewData.state()).frame(
        width: 900,
        height: 640
    )
}

#Preview("Dock to launcher transition") {
    LauncherTransitionPreview()
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
