import AppKit
import Foundation
import Testing
@testable import DeeDock

struct WindowPeekTests {
    @Test("Named presets apply exact values and custom combinations have no name",
          arguments: WindowPeekPreset.allCases)
    func presets(_ preset: WindowPeekPreset) {
        var settings = DockSettings.defaults
        preset.apply(to: &settings)
        #expect(WindowPeekPreset.matching(settings) == preset)
        settings.windowPeekIncludeUntitled.toggle()
        #expect(WindowPeekPreset.matching(settings) == nil)
    }

    @Test("Fallback projection remains usable for every permission and result state")
    func fallbackProjection() {
        #expect(WindowPeekPresentationProjection.settledPhase(
            windowAccess: .notEnabled, discoveredCount: 3, filteredCount: 3) == .appFallback)
        #expect(WindowPeekPresentationProjection.settledPhase(
            windowAccess: .enabled, discoveredCount: 0, filteredCount: 0) == .noWindows)
        #expect(WindowPeekPresentationProjection.settledPhase(
            windowAccess: .enabled, discoveredCount: 3, filteredCount: 0) == .noMatch)
        #expect(WindowPeekPresentationProjection.settledPhase(
            windowAccess: .enabled, discoveredCount: 3, filteredCount: 2) == .windows)
        #expect(WindowPeekPhase.discoveryFailed(.sandboxRestricted)
            != .appFallback)
    }

    @Test("Pointer travel retains Peek and stale generations are rejected")
    func lifecycleProjection() {
        #expect(WindowPeekLifecycle.retainsPresentation(sourceHovered: true, panelHovered: false))
        #expect(WindowPeekLifecycle.retainsPresentation(sourceHovered: false, panelHovered: true))
        #expect(!WindowPeekLifecycle.retainsPresentation(sourceHovered: false, panelHovered: false))

        let current = UUID()
        #expect(WindowPeekLifecycle.acceptsResult(expected: current, current: current))
        #expect(!WindowPeekLifecycle.acceptsResult(expected: UUID(), current: current))
    }

    @Test("Hover delay is bounded and snapped to one tenth of a second")
    func hoverDelayValidation() {
        var settings = DockSettings.defaults
        settings.windowPeekHoverDelay = 0.46
        #expect(settings.normalized?.windowPeekHoverDelay == 0.5)
        settings.windowPeekHoverDelay = 1.1
        #expect(settings.normalized == nil)
    }

    @Test("Window matching requires a unique PID, title, and near-identical frame")
    func conservativeMatching() {
        let session = UUID()
        let first = summary(session: session, pid: 40, title: "Report", x: 100)
        let second = summary(session: session, pid: 40, title: nil, x: 500)
        let candidates = [
            WindowCaptureCandidate(id: 1, processIdentifier: 40, title: "Report",
                                   frame: CGRect(x: 101, y: 100, width: 800, height: 600), isOnScreen: true),
            WindowCaptureCandidate(id: 2, processIdentifier: 40, title: nil,
                                   frame: CGRect(x: 500, y: 100, width: 800, height: 600), isOnScreen: true),
        ]
        let matches = WindowThumbnailMatcher.matches(summaries: [first, second], candidates: candidates)
        #expect(matches[first.token] == 1)
        #expect(matches[second.token] == 2)

        let ambiguous = candidates + [WindowCaptureCandidate(id: 3, processIdentifier: 40, title: "Report",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), isOnScreen: true)]
        #expect(WindowThumbnailMatcher.matches(summaries: [first], candidates: ambiguous)[first.token] == nil)
    }

    @Test("Screen capture discovery keeps sized windows for the requested processes and flags off-screen ones")
    func screenCaptureDiscovery() {
        let session = UUID()
        let candidates = [
            WindowCaptureCandidate(id: 1, processIdentifier: 40, title: "Report",
                                   frame: CGRect(x: 10, y: 20, width: 800, height: 600), isOnScreen: true),
            WindowCaptureCandidate(id: 2, processIdentifier: 41, title: "Other",
                                   frame: CGRect(x: 10, y: 20, width: 800, height: 600), isOnScreen: true),
            WindowCaptureCandidate(id: 3, processIdentifier: 40, title: "Zero",
                                   frame: CGRect(x: 10, y: 20, width: 0, height: 600), isOnScreen: true),
            WindowCaptureCandidate(id: 4, processIdentifier: 40, title: "Off-screen helper",
                                   frame: CGRect(x: 10, y: 20, width: 800, height: 600), isOnScreen: false),
        ]
        let summaries = WindowCaptureDiscovery.summaries(
            candidates: candidates, processIdentifiers: [40], sessionID: session)
        #expect(summaries.count == 2)
        #expect(summaries.allSatisfy { $0.processIdentifier == 40 && $0.token.sessionID == session })
        #expect(summaries[0].isOffScreen == false)
        // A hidden, minimized, or other-Space window keeps a card rather than emptying the Peek.
        #expect(summaries[1].title == "Off-screen helper")
        #expect(summaries[1].isOffScreen)
        #expect(summaries[1].isMinimized == false)
    }

    @Test("Thumbnail cache reuses a picture only for the same process launch, window size, and pixel budget")
    func thumbnailCacheValidity() throws {
        var cache = WindowThumbnailCache(capacity: 4)
        let key = WindowThumbnailCache.Key(processIdentifier: 40, windowID: 7)
        let launch = Date(timeIntervalSince1970: 1_000)
        let size = CGSize(width: 800, height: 600)
        let budget = CGSize(width: 400, height: 250)
        let image = try #require(Self.bitmap())
        cache.store(image, for: key, sourceSize: size, budget: budget, launchDate: launch)

        #expect(cache.image(for: key, sourceSize: size, budget: budget, launchDate: launch) === image)
        // The matcher's two-point tolerance applies to the window size.
        #expect(cache.image(for: key, sourceSize: CGSize(width: 802, height: 598), budget: budget, launchDate: launch) != nil)
        #expect(cache.image(for: key, sourceSize: CGSize(width: 803, height: 600), budget: budget, launchDate: launch) == nil)
        #expect(cache.image(for: key, sourceSize: size, budget: CGSize(width: 800, height: 500), launchDate: launch) == nil)
        #expect(cache.image(for: key, sourceSize: size, budget: budget, launchDate: launch + 1) == nil)
        #expect(cache.image(for: WindowThumbnailCache.Key(processIdentifier: 41, windowID: 7),
                            sourceSize: size, budget: budget, launchDate: launch) == nil)

        cache.removeAll(for: 40)
        #expect(cache.image(for: key, sourceSize: size, budget: budget, launchDate: launch) == nil)
    }

    @Test("Thumbnail cache evicts the least recently used picture past its capacity")
    func thumbnailCacheEviction() throws {
        var cache = WindowThumbnailCache(capacity: 2)
        let image = try #require(Self.bitmap())
        let size = CGSize(width: 800, height: 600)
        let budget = CGSize(width: 400, height: 250)
        func key(_ id: CGWindowID) -> WindowThumbnailCache.Key { .init(processIdentifier: 40, windowID: id) }
        cache.store(image, for: key(1), sourceSize: size, budget: budget, launchDate: nil)
        cache.store(image, for: key(2), sourceSize: size, budget: budget, launchDate: nil)
        // Touching window 1 makes window 2 the eviction candidate.
        #expect(cache.image(for: key(1), sourceSize: size, budget: budget, launchDate: nil) != nil)
        cache.store(image, for: key(3), sourceSize: size, budget: budget, launchDate: nil)
        #expect(cache.count == 2)
        #expect(cache.image(for: key(1), sourceSize: size, budget: budget, launchDate: nil) != nil)
        #expect(cache.image(for: key(2), sourceSize: size, budget: budget, launchDate: nil) == nil)
        #expect(cache.image(for: key(3), sourceSize: size, budget: budget, launchDate: nil) != nil)
    }

    private static func bitmap() -> CGImage? {
        CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    @Test("Panel geometry points inward and clamps on negative-origin displays",
          arguments: DockEdge.allCases)
    func geometry(_ edge: DockEdge) {
        let visible = CGRect(x: -1800, y: -200, width: 1400, height: 900)
        let anchor = WindowPeekAnchor(icon: CGRect(x: -1760, y: 600, width: 48, height: 48),
                                      edge: edge, visibleFrame: visible)
        let placement = WindowPeekGeometry.placement(anchor: anchor, settings: .defaults, count: 8)
        let safe = visible.insetBy(dx: WindowPeekGeometry.screenMargin, dy: WindowPeekGeometry.screenMargin)
        #expect(placement.frame.minX >= safe.minX)
        #expect(placement.frame.maxX <= safe.maxX)
        #expect(placement.frame.minY >= safe.minY)
        #expect(placement.frame.maxY <= safe.maxY)
    }

    @Test("A 2× display captures the logical thumbnail in backing pixels, without halving it",
          arguments: WindowPeekSize.allCases)
    func retinaCaptureBudget(_ peekSize: WindowPeekSize) {
        let logical = peekSize.thumbnailSize
        let budget = WindowScreenshot.backingPixels(for: logical, pointPixelScale: 2)
        #expect(budget == CGSize(width: logical.width * 2, height: logical.height * 2))
        // 2048×1280 is the same 8:5 shape as the thumbnails, so the fitted bitmap is the budget.
        let fitted = WindowScreenshot.outputPixels(source: CGSize(width: 2048, height: 1280), fittingPixels: budget)
        #expect(fitted == budget)
        #expect(WindowScreenshot.backingPixels(for: logical, pointPixelScale: 1) == logical)
        #expect(WindowScreenshot.backingPixels(for: logical, pointPixelScale: 0) == logical)
    }

    @Test("Short content keeps the panel edge that faces the dock icon", arguments: DockEdge.allCases)
    func fittedHeightHugsTheIcon(_ edge: DockEdge) {
        let placement = WindowPeekPlacement(frame: CGRect(x: 100, y: 200, width: 400, height: 300), edge: edge)
        let fitted = WindowPeekGeometry.fitted(placement, contentHeight: 120)
        #expect(fitted.height == 120)
        #expect(fitted.width == placement.frame.width)
        switch edge {
        case .bottom: #expect(fitted.minY == placement.frame.minY)
        case .top: #expect(fitted.maxY == placement.frame.maxY)
        case .left, .right: #expect(fitted.midY == placement.frame.midY)
        }
        // Content taller than the sized panel never grows it past the clamped placement.
        #expect(WindowPeekGeometry.fitted(placement, contentHeight: 900) == placement.frame)
    }

    private func summary(session: UUID, pid: pid_t, title: String?, x: CGFloat) -> ApplicationWindowSummary {
        ApplicationWindowSummary(token: ApplicationWindowToken(sessionID: session, id: UUID()),
                                 processIdentifier: pid, title: title,
                                 frame: CGRect(x: x, y: 100, width: 800, height: 600),
                                 isMinimized: false, isMain: false)
    }
}

@MainActor
struct ScreenCapturePermissionTests {
    @Test("Screen Recording checks stay read-only until Enable is chosen")
    func explicitRequest() {
        let service = StubScreenCaptureAccessService()
        let controller = ScreenCaptureAccessController(service: service)
        controller.refresh()
        #expect(service.requests == 0)
        controller.requestAccess()
        #expect(service.requests == 1)
        controller.openSystemSettings()
        #expect(service.settingsOpens == 1)
    }
}

@MainActor
private final class StubScreenCaptureAccessService: ScreenCaptureAccessServicing {
    var status: ScreenCaptureAccessStatus = .notEnabled
    var requests = 0
    var settingsOpens = 0
    func requestAccess() { requests += 1 }
    func openSystemSettings() { settingsOpens += 1 }
}
