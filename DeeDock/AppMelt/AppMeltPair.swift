import AppKit
import Observation

/// One session-only pair. Window tokens never survive relaunch or bind to a replacement window.
@MainActor @Observable final class AppMeltPair: Identifiable {
    let id = UUID()
    let sessionID: UUID
    var windows: [ApplicationWindowSummary]
    var names: [String]
    var icons: [NSImage]
    /// Matches DockItem identity without changing the saved pin or running-app order.
    var applicationIDs: [String]
    var frame: CGRect
    var ratio = 0.5
    var layoutPopover = false {
        didSet { if oldValue != layoutPopover { chromeInteractionChanged?() } }
    }
    /// Native menu tracking spans its entire submenu tree, without invalidating SwiftUI layout.
    @ObservationIgnored var isTrackingToolbarMenu = false
    @ObservationIgnored var chromeInteractionChanged: (() -> Void)?
    var sidesSwapped = false
    var undoLayout: AppMeltLayoutSnapshot?
    var fittedFrom: AppMeltLayoutSnapshot?
    @ObservationIgnored var gestureStart: AppMeltLayoutSnapshot?
    @ObservationIgnored var replacement: AppMeltWindowPickerState?
    @ObservationIgnored var comparison: FusionCoordinator?
    var layoutTokens: [ApplicationWindowToken] { sidesSwapped ? Array(tokens.reversed()) : tokens }
    var orderedNames: [String] { sidesSwapped ? Array(names.reversed()) : names }
    var canChangeLayout: Bool {
        !busy && !isDragging && !suspended && !minimized
            && finderTools?.busy != true && finderTools?.isChoosingFolder != true
    }
    var needsReveal = true
    var minimized = false
    var busy = false
    /// Explicit pair operations show progress; geometry updates only use the busy guard.
    var showsOperationProgress = false
    var message: LocalizedStringResource?
    @ObservationIgnored var chrome: AppMeltChrome?
    @ObservationIgnored var finderTools: MeltFinderState?
    @ObservationIgnored let observation = AppMeltObservation()
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var isDragging = false
    @ObservationIgnored var pendingFrame: CGRect?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var acceptedFrames: [CGRect] = []
    @ObservationIgnored var suspended = false
    @ObservationIgnored var foreground = false
    /// Chrome follows the accepted native frames, including app-enforced minimum sizes.
    func accept(_ frames: [CGRect]) {
        guard frames.count == 2,
              frames.allSatisfy({ WindowPlacementPolicy.valid($0) }),
              frames[0].width + frames[1].width > 0 else { return }
        acceptedFrames = frames
        let bounds = frames[0].union(frames[1])
        frame = CGRect(x: bounds.minX - AppMeltGeometry.rim, y: bounds.minY - AppMeltGeometry.header,
                       width: bounds.width + AppMeltGeometry.rim * 2,
                       height: bounds.height + AppMeltGeometry.header + AppMeltGeometry.rim)
        ratio = frames[0].width / (frames[0].width + frames[1].width)
    }

    /// The second window of a same-app pair needs its own hit/keyboard identity.
    /// The first member retains the app identity for its transition out of the ordinary dock.
    func dockIdentity(at index: Int) -> DockEntryID {
        index == 1 && applicationIDs[0] == applicationIDs[1] ? .melt(id) : .app(applicationIDs[index])
    }

    var tokens: [ApplicationWindowToken] { windows.map(\.token) }
    var title: String { orderedNames.joined(separator: " + ") }

    init(sessionID: UUID, windows: [ApplicationWindowSummary], names: [String], icons: [NSImage], frame: CGRect) {
        self.sessionID = sessionID
        self.windows = windows
        self.names = names
        self.icons = icons
        self.applicationIDs = windows.map { window in
            let app = NSRunningApplication(processIdentifier: window.processIdentifier)
            return app?.bundleIdentifier ?? app?.bundleURL?.standardizedFileURL.path ?? "process:\(window.processIdentifier)"
        }
        self.frame = frame
    }
}
