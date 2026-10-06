#if DEBUG
import SwiftUI

/// Deterministic apps and symbol artwork. No discovery, launches, or real preferences are used.
@MainActor
private enum CompactLauncherPreviewData {
    static let names = ["Safari", "Mail", "Calendar", "Photos", "Notes", "Reminders",
                        "Music", "Maps", "Messages", "FaceTime", "App Store", "System Settings",
                        "Pages", "Numbers", "Keynote", "Preview", "Terminal", "ChatGPT", "Atlas"]

    static func model(lineIcons: Bool = false, query: String = "") -> CompactLauncherModel {
        let applications = names.enumerated().map { index, name in
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "preview.\(index)",
                url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name))
        }
        let catalog = ApplicationCatalog(service: ApplicationService(),
                                         launcherLibrary: LauncherLibrary(applications: applications))
        let launcher = LauncherState(catalog: catalog) { _ in
            NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 64, height: 64))
        }
        launcher.usesLineIcons = lineIcons
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
