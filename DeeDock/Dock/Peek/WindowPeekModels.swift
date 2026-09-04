import AppKit
import Observation

nonisolated enum WindowPeekPhase: Equatable, Sendable {
    case loading
    case windows
    case appFallback
    case discoveryFailed(ApplicationWindowDiscoveryFailure)
    case noWindows
    case noMatch
}

nonisolated enum WindowPeekPresentationProjection {
    static func settledPhase(windowAccess: WindowAccessStatus,
                             discoveredCount: Int, filteredCount: Int) -> WindowPeekPhase {
        guard windowAccess == .enabled else { return .appFallback }
        if discoveredCount == 0 { return .noWindows }
        if filteredCount == 0 { return .noMatch }
        return .windows
    }
}

/// Pure lifecycle rules keep pointer travel and asynchronous result rejection testable.
nonisolated enum WindowPeekLifecycle {
    static func retainsPresentation(sourceHovered: Bool, panelHovered: Bool) -> Bool {
        sourceHovered || panelHovered
    }

    static func acceptsResult(expected: UUID, current: UUID) -> Bool {
        expected == current
    }
}

struct WindowPeekCard: Identifiable {
    let window: ApplicationWindowSummary
    var thumbnail: CGImage?
    var id: ApplicationWindowToken { window.token }
}

/// UI state for one transient Peek presentation.
@MainActor @Observable
final class WindowPeekState {
    let appName: String
    let appIcon: NSImage
    var settings: DockSettings
    var phase: WindowPeekPhase = .loading
    var cards: [WindowPeekCard] = []
    var selectedID: ApplicationWindowToken?
    /// ScreenCaptureKit-only cards can be previewed, but selecting one can only activate its app.
    var usesApplicationSelection = false
    @ObservationIgnored var choose: ((ApplicationWindowToken) -> Void)?
    @ObservationIgnored var showApp: (() -> Void)?
    @ObservationIgnored var settingsSelected: (() -> Void)?
    @ObservationIgnored var showAll: (() -> Void)?
    @ObservationIgnored var hovered: ((Bool) -> Void)?
    @ObservationIgnored var thumbnailNeeded: ((ApplicationWindowToken) -> Void)?

    init(item: DockItem, settings: DockSettings) {
        appName = item.reference.name
        appIcon = item.icon
        self.settings = settings
    }

    func select(by distance: Int) {
        guard !cards.isEmpty else { return }
        let index = selectedID.flatMap { id in cards.firstIndex { $0.id == id } } ?? 0
        selectedID = cards[(index + distance + cards.count) % cards.count].id
    }

    func chooseSelection() {
        guard let selectedID else { showApp?(); return }
        choose?(selectedID)
    }
}

nonisolated struct WindowPeekAnchor: Equatable, Sendable {
    let icon: CGRect
    let edge: DockEdge
    let visibleFrame: CGRect
}

nonisolated struct WindowPeekPlacement: Equatable, Sendable {
    let frame: CGRect
    let edge: DockEdge
}
