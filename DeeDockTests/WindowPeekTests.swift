import AppKit
import Foundation
import Testing

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

    @Test("Screen capture discovery keeps only visible-sized windows for the requested processes")
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
        #expect(summaries.count == 1)
        #expect(summaries[0].processIdentifier == 40)
        #expect(summaries[0].token.sessionID == session)
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
