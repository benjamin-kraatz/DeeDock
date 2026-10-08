#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Deterministic Harbor scenes for previews. Nothing here reads live windows, captures the screen,
/// or activates an app; thumbnails are absent, so tiles show their placeholders.
enum HarborPreviewScenario {
    case typical, many, crowded, noAccessibility, empty
}

/// Ignores every intent, so previews can be clicked safely.
@MainActor
final class HarborPreviewIntents: HarborIntents {
    func activate(_ id: UUID) {}
    func closeWindow(_ id: UUID) {}
    func stripTapped(_ appID: String, displayID: String) {}
    func dismiss() {}
    func prepareSettings() {}
}

@MainActor
enum HarborPreviewData {
    static let size = CGSize(width: 1280, height: 800)

    /// One app in a scene: identity, name, and windows as title, size, state, and document.
    private struct SampleApp {
        let id: String
        let name: String
        let windows: [(String, CGSize, HarborWindowState, String?)]
    }

    private static func sampleApps(_ scenario: HarborPreviewScenario) -> [SampleApp] {
        switch scenario {
        case .empty:
            return []
        case .many:
            return (0..<9).map { app in
                SampleApp(id: "app.\(app)", name: "App \(app + 1)", windows: (0..<(app % 4 + 1)).map { index in
                    ("Window \(index + 1)", CGSize(width: 600 + index * 40, height: 420), HarborWindowState.visible, nil)
                })
            }
        case .crowded:
            return (0..<14).map { app in
                SampleApp(id: "app.\(app)", name: "App \(app + 1)", windows: (0..<(app % 5 + 3)).map { index in
                    ("Window \(index + 1)", CGSize(width: 640, height: 400), HarborWindowState.visible, nil)
                })
            }
        case .typical, .noAccessibility:
            return [
                SampleApp(id: "com.apple.Safari", name: "Safari", windows: [
                    ("Getting Started – DOKK", CGSize(width: 760, height: 500), .visible, "https://docs.example/dokk/"),
                    ("Architektur für morgen", CGSize(width: 720, height: 480), .visible, "https://www.studio.example/architektur"),
                    ("Projektübersicht", CGSize(width: 700, height: 470), .visible, "https://projekt.example/overview?tab=1")]),
                SampleApp(id: "com.apple.TextEdit", name: "TextEdit", windows: [
                    ("Angebot.rtf — Bearbeitet", CGSize(width: 520, height: 600), .visible, "file:///Users/preview/Documents/Angebot.rtf")]),
                SampleApp(id: "com.apple.finder", name: "Finder", windows: [
                    ("Dokumente", CGSize(width: 640, height: 400), .visible, "file:///Users/preview/Documents/"),
                    ("Downloads", CGSize(width: 600, height: 380), .visible, "file:///Users/preview/Downloads/")]),
                SampleApp(id: "com.apple.mail", name: "Mail", windows: [
                    ("Eingang – 12 ungelesen", CGSize(width: 800, height: 480), .visible, nil),
                    ("Angebot für Weber", CGSize(width: 600, height: 460), .minimized, nil)]),
                SampleApp(id: "com.apple.Preview", name: "Vorschau", windows: [
                    ("Hausentwurf.pdf", CGSize(width: 500, height: 620), .visible, "file:///Users/preview/Documents/Architecture/Hausentwurf.pdf"),
                    ("Küste und Licht.pdf", CGSize(width: 500, height: 620), .visible, "file:///Users/preview/Documents/Inspiration/K%C3%BCste%20und%20Licht.pdf")]),
                SampleApp(id: "com.apple.Music", name: "Musik", windows: [
                    ("Musik", CGSize(width: 760, height: 480), .hidden, nil)]),
            ]
        }
    }

    /// A bottom dock as the strip sees it: three pinned apps that are not running, the running
    /// apps of the typical scene, the Harbor tile, and the Trash, at resting size.
    static var dockSeed: HarborDockSeed {
        let icon: CGFloat = 48
        let ids: [(String, HarborDockSeed.Tile.Kind)] = [
            ("app:com.apple.finder", .app(appID: "com.apple.finder", running: true)),
            ("app:com.apple.Notes", .app(appID: "com.apple.Notes", running: false)),
            ("app:com.apple.Safari", .app(appID: "com.apple.Safari", running: true)),
            ("app:com.apple.Calendar", .app(appID: "com.apple.Calendar", running: false)),
            ("app:com.apple.mail", .app(appID: "com.apple.mail", running: true)),
            ("app:com.apple.Photos", .app(appID: "com.apple.Photos", running: false)),
            ("app:com.apple.Preview", .app(appID: "com.apple.Preview", running: true)),
            ("harbor", .harbor),
            ("trash", .other),
        ]
        let length = CGFloat(ids.count) * (icon + 8) + 12
        let glass = CGRect(x: (size.width - length) / 2, y: size.height - 8 - icon - 16, width: length, height: icon + 16)
        let tiles = ids.enumerated().map { index, entry in
            HarborDockSeed.Tile(id: entry.0, kind: entry.1,
                                frame: CGRect(x: glass.minX + 6 + CGFloat(index) * (icon + 8) + 4, y: glass.minY + 6, width: icon, height: icon),
                                icon: NSWorkspace.shared.icon(for: .application))
        }
        return HarborDockSeed(glass: glass, cornerRadius: 22, tiles: tiles)
    }

    static func session(_ scenario: HarborPreviewScenario, reduceTransparency: Bool = false) -> HarborSession {
        let apps = sampleApps(scenario)
        var stack = 0
        var windows: [HarborWindow] = []
        for app in apps {
            for (title, size, state, document) in app.windows {
                let frame = CGRect(x: CGFloat(80 + stack * 30), y: CGFloat(60 + stack * 20), width: size.width, height: size.height)
                let token = scenario == .noAccessibility ? nil : ApplicationWindowToken(sessionID: UUID(), id: UUID())
                windows.append(HarborWindow(id: UUID(), appID: app.id, processIdentifier: 1, title: title, frame: frame,
                                            state: state, token: token, captureID: nil, stackOrder: stack, document: document))
                stack += 1
            }
        }
        let running = apps.map { HarborRunningApp(id: $0.id, name: $0.name, processIdentifier: 1, isHidden: false, isActive: false) }
        let bounds = ["preview": CGRect(origin: .zero, size: size)]
        let content = HarborDisplayContent(
            displayID: "preview", size: size, quartzOrigin: .zero, stripEdge: .bottom, wallpaper: nil,
            groups: HarborGrouping.groups(windows: windows, apps: running, displayBounds: bounds, displayID: "preview"),
            stripApps: running.map { HarborStripApp(id: $0.id, name: $0.name, processIdentifier: 1) },
            dockSeed: scenario == .typical ? dockSeed : nil)
        let session = HarborSession()
        session.begin(displays: ["preview": content], keyDisplayID: "preview",
                      access: HarborAccess(windows: scenario != .noAccessibility, thumbnails: false),
                      icons: [:], reduceMotion: false, reduceTransparency: reduceTransparency)
        session.reveal()
        return session
    }
}

/// Renders one scenario at display size, scaled down to fit the canvas.
struct HarborPreviewHost: View {
    let scenario: HarborPreviewScenario
    var reduceTransparency = false
    @State private var session: HarborSession?
    @State private var intents = HarborPreviewIntents()

    var body: some View {
        Group {
            if let session {
                HarborView(session: session, displayID: "preview", intents: intents)
                    .frame(width: HarborPreviewData.size.width, height: HarborPreviewData.size.height)
                    .scaleEffect(0.6)
                    .frame(width: HarborPreviewData.size.width * 0.6, height: HarborPreviewData.size.height * 0.6)
            }
        }
        .onAppear { session = HarborPreviewData.session(scenario, reduceTransparency: reduceTransparency) }
    }
}
#endif
