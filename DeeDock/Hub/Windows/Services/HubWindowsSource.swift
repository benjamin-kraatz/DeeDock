import AppKit
import UniformTypeIdentifiers

/// A running app with its icon, read on the main actor.
struct HubRunningApp {
    let app: HarborRunningApp
    let icon: NSImage
}

/// Where the Windows tab gets its windows, thumbnails, and activation from.
///
/// The live source reuses Radar's discovery (``HarborWindowService``); previews and tests inject
/// a stub so they never touch the workspace, permissions, or other apps.
@MainActor
protocol HubWindowsSource: AnyObject {
    /// Regular running apps other than DOKK, in workspace order.
    func runningApps() -> [HubRunningApp]

    /// Finds the windows of `apps` in the current Space plus their minimized and hidden windows.
    /// Starting a new discovery releases the previous one's window handles.
    func discover(apps: [HarborRunningApp]) async -> HarborDiscovery

    /// Captures one window fitted into `pixels`, or nil when it is gone, protected, or Screen
    /// Recording is off. Runs off the main actor.
    func thumbnail(_ number: CGWindowID, fittingPixels pixels: CGSize) async -> CGImage?

    /// Brings `window` forward: unhides its app, unminimizes it, and raises the exact window when
    /// Accessibility allows, otherwise activates its app.
    func activate(_ window: HarborWindow) async

    /// Releases the handles of discovery `session`, unless a newer discovery replaced it.
    func end(session: UUID) async
}

/// The live source, backed by its own ``HarborWindowService`` so the Hub and Radar never share a session.
@MainActor
final class HarborHubWindowsSource: HubWindowsSource {
    private let service = HarborWindowService()

    func runningApps() -> [HubRunningApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != own else { return nil }
            let id = app.bundleIdentifier ?? app.bundleURL?.standardizedFileURL.path ?? "pid:\(app.processIdentifier)"
            let running = HarborRunningApp(id: id, name: app.localizedName ?? "", processIdentifier: app.processIdentifier,
                                           isHidden: app.isHidden, isActive: app.isActive)
            return HubRunningApp(app: running, icon: app.icon ?? NSWorkspace.shared.icon(for: .application))
        }
    }

    func discover(apps: [HarborRunningApp]) async -> HarborDiscovery {
        await service.discover(apps: apps)
    }

    func thumbnail(_ number: CGWindowID, fittingPixels pixels: CGSize) async -> CGImage? {
        await service.thumbnail(number, fittingPixels: pixels)
    }

    func activate(_ window: HarborWindow) async {
        let app = NSRunningApplication(processIdentifier: window.processIdentifier)
        if window.state == .hidden { app?.unhide() }
        // `raise` unminimizes, activates the owner, and raises the exact window.
        if let token = window.token, (try? await service.raise(token)) != nil { return }
        app?.unhide()
        app?.activate(options: [])
    }

    func end(session: UUID) async {
        await service.end(session: session)
    }
}
