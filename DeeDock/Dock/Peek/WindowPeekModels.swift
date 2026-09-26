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
    /// The ordinary layout stays available for this presentation without changing preferences.
    var showsAllWindows = false
    var splitFitsDisplay = true

    /// The selected window and its neighbor in discovery order, with the main window first initially.
    var splitCandidates: [WindowPeekCard] {
        guard settings.windowPeekSplitEnabled, !routingFiles, !showsAllWindows,
              splitFitsDisplay, phase == .windows, cards.count >= 2 else { return [] }
        let index = selectedID.flatMap { id in cards.firstIndex { $0.id == id } } ?? 0
        let start = min(index, cards.count - 2)
        return Array(cards[start...start + 1])
    }

    /// Never present a split with an icon placeholder in place of either window's content.
    var splitCards: [WindowPeekCard] {
        let candidates = splitCandidates
        return candidates.count == 2 && candidates.allSatisfy { $0.thumbnail != nil } ? candidates : []
    }
    /// ScreenCaptureKit-only cards can be previewed, but selecting one can only activate its app.
    var usesApplicationSelection = false
    var actionBusy = false
    var actionMenuTracking = false
    var actionMessage: LocalizedStringResource?
    @ObservationIgnored var manage: ((ApplicationWindowToken) -> Void)?
    var routingFiles = false
    var receivingFileDrag = false
    @ObservationIgnored var chooseFiles: (() -> Void)?
    @ObservationIgnored var fileDragUpdated: ((NSDraggingInfo, ApplicationWindowToken?) -> Bool)?
    @ObservationIgnored var fileDrop: ((NSDraggingInfo, ApplicationWindowToken?) -> Bool)?
    @ObservationIgnored var fileDragExited: (() -> Void)?
    @ObservationIgnored var fileDragEnded: (() -> Void)?
    @ObservationIgnored var watch: ((ApplicationWindowToken) -> Void)?
    /// Opens the markup editor for a card's window. Closes Peek.
    @ObservationIgnored var markup: ((ApplicationWindowToken) -> Void)?
    var portalDragging = false
    @ObservationIgnored var portalTracking: ((Bool) -> Void)?
    @ObservationIgnored var dropPortal: ((ApplicationWindowSummary, CGPoint, Bool) -> Void)?
    @ObservationIgnored var pinFrozen: ((ApplicationWindowSummary) -> Void)?
    @ObservationIgnored var pinPortal: ((ApplicationWindowSummary) -> Void)?
    @ObservationIgnored var startMelt: ((ApplicationWindowSummary) -> Void)?
    @ObservationIgnored var addToFusion: ((ApplicationWindowSummary) -> Void)?
    @ObservationIgnored var choose: ((ApplicationWindowToken) -> Void)?
    @ObservationIgnored var showApp: (() -> Void)?
    @ObservationIgnored var settingsSelected: (() -> Void)?
    @ObservationIgnored var showAll: (() -> Void)?
    @ObservationIgnored var hovered: ((Bool) -> Void)?
    @ObservationIgnored var thumbnailNeeded: ((ApplicationWindowToken) -> Void)?
    /// The card whose image is lifted onto the enlarged-preview stage; its slot shows a placeholder.
    var liftedID: ApplicationWindowToken?
    /// Latest artwork frame per card in the Peek panel's top-left-origin SwiftUI space. Unobserved:
    /// it feeds the enlarged preview's flight geometry and must not re-render the cards.
    @ObservationIgnored var artworkFrames: [ApplicationWindowToken: CGRect] = [:]
    /// Pointer entered (`true`) or left a card. Set only while the enlarged preview is enabled.
    @ObservationIgnored var cardHovered: ((ApplicationWindowToken, Bool) -> Void)?

    /// Whether cards report hover and artwork frames for the enlarged preview.
    var enlargesCards: Bool { settings.windowPeekEnlargeEnabled && !routingFiles }

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
