import AppKit
import OSLog
import ScreenCaptureKit

/// Finds, captures, raises, and closes windows for one Harbor session at a time.
///
/// Accessibility handles live in the wrapped ``AccessibilityApplicationWindowService`` and
/// ScreenCaptureKit windows live in this actor; neither leaves it. Every capture is a one-shot,
/// memory-only screenshot at thumbnail size. Discovery and capture never prompt for permission.
actor HarborWindowService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "Harbor")

    private let accessibility = AccessibilityApplicationWindowService(maximumWindows: 400)
    private var shareable: [CGWindowID: SCWindow] = [:]
    private var sessionID: UUID?

    /// Gathers every window of `apps` in the current Space, plus their minimized and hidden windows.
    func discover(apps: [HarborRunningApp]) async -> HarborDiscovery {
        let session = UUID()
        shareable = [:]
        sessionID = session
        await accessibility.stop()
        guard sessionID == session, !Task.isCancelled else { return Self.emptyDiscovery(session) }
        var screen = Self.screenWindows()
        var capturable: Set<CGWindowID>?
        if CGPreflightScreenCaptureAccess() {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard sessionID == session, !Task.isCancelled else { return Self.emptyDiscovery(session) }
                shareable = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                capturable = Set(shareable.keys)
                for index in screen.indices {
                    screen[index].title = shareable[screen[index].number]?.title.flatMap { $0.isEmpty ? nil : $0 }
                }
            } catch {
                Self.logger.error("Harbor window enumeration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        var summaries: [ApplicationWindowSummary]?
        if AXIsProcessTrusted() {
            let processes = apps.map {
                ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier, isHidden: $0.isHidden, isActive: $0.isActive)
            }
            summaries = try? await accessibility.discover(processes: processes, sessionID: session)
        }
        guard sessionID == session, !Task.isCancelled else { return Self.emptyDiscovery(session) }
        let windows = HarborDiscoveryProjection.windows(apps: apps, accessibility: summaries, screen: screen,
                                                         capturable: capturable)
        return HarborDiscovery(windows: windows, access: HarborAccess(windows: summaries != nil, thumbnails: capturable != nil),
                               sessionID: session)
    }

    private static func emptyDiscovery(_ session: UUID) -> HarborDiscovery {
        HarborDiscovery(windows: [], access: HarborAccess(windows: false, thumbnails: false), sessionID: session)
    }

    /// Captures and classifies the window resolved by `session`. Returns nil if discovery replaced it.
    func thumbnail(_ number: CGWindowID, fittingPixels pixels: CGSize, session: UUID) async -> ClassifiedWindowPreview? {
        guard sessionID == session, let window = shareable[number] else { return nil }
        do {
            let image = try await WindowScreenshot.capture(window, fittingPixels: pixels)
            guard sessionID == session, !Task.isCancelled else { return nil }
            let preview = await ClassifiedWindowPreview.classify(image, using: CoreMLWindowPreviewClassifier.shared)
            return sessionID == session && !Task.isCancelled ? preview : nil
        } catch is CancellationError {
            return nil
        } catch {
            Self.logger.error("Harbor thumbnail capture failed")
            return nil
        }
    }

    /// Unminimizes when needed, activates the owning app, and raises the exact window.
    func raise(_ token: ApplicationWindowToken) async throws {
        try await accessibility.selectWindow(token)
    }

    /// Presses the window's own Close button. The app is activated first, as Window Peek does,
    /// so a save dialog can appear.
    func close(_ token: ApplicationWindowToken, displays: [WindowActionDisplay]) async throws {
        _ = try await accessibility.perform(.close, token: token, displays: displays)
    }

    /// Looks for `window` again after a Close. A window that survives is usually showing a save
    /// sheet; the returned token can raise it.
    func survivor(of window: HarborWindow) async -> ApplicationWindowToken? {
        guard AXIsProcessTrusted() else { return nil }
        let session = UUID()
        let process = ApplicationProcessSnapshot(processIdentifier: window.processIdentifier, isHidden: false, isActive: true)
        guard let summaries = try? await accessibility.discover(processes: [process], sessionID: session) else { return nil }
        let source = ApplicationWindowSummary(token: ApplicationWindowToken(sessionID: UUID(), id: UUID()),
                                              processIdentifier: window.processIdentifier, title: window.title,
                                              frame: window.frame, isMinimized: false, isMain: false)
        return WindowThumbnailMatcher.matchingWindow(source, among: summaries)
    }

    /// Releases the handles of `session`, unless a newer session has started since.
    func end(session: UUID) async {
        guard sessionID == session else { return }
        await end()
    }

    private func end() async {
        shareable = [:]
        sessionID = nil
        await accessibility.stop()
    }

    /// On-screen layer-0 windows, front to back, excluding DOKK's own.
    private static func screenWindows() -> [HarborScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return HarborScreenWindow(number: number, processIdentifier: pid, frame: frame, title: nil)
        }
    }
}
