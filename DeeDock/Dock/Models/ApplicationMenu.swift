import Foundation

/// Current authorization state for reading and controlling another application's windows.
nonisolated enum WindowAccessStatus: Equatable, Sendable {
    case enabled
    case notEnabled
    case unavailable
}

/// A process resolved from a dock application's stable bundle or URL identity.
nonisolated struct ApplicationProcessSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let isHidden: Bool
    let isActive: Bool
}

/// Opaque identity for one Accessibility window, valid only for its menu session.
nonisolated struct ApplicationWindowToken: Hashable, Sendable {
    let sessionID: UUID
    let id: UUID
}

/// Display-safe window metadata. Native Accessibility handles never leave their service actor.
nonisolated struct ApplicationWindowSummary: Equatable, Identifiable, Sendable {
    let token: ApplicationWindowToken
    let processIdentifier: pid_t
    let title: String?
    /// Global Quartz window bounds used only for conservative ScreenCaptureKit matching.
    let frame: CGRect?
    let isMinimized: Bool
    let isMain: Bool
    /// `AXDocument`: the file or web URL the window shows, when the app reports one.
    var document: String? = nil

    var id: ApplicationWindowToken { token }
}

/// A display-safe reason why a granted window query could not produce summaries.
nonisolated enum ApplicationWindowDiscoveryFailure: Equatable, Sendable {
    case permissionRequired
    case sandboxRestricted
    case applicationUnavailable
    case windowUnavailable
    case accessibility(Int32)
    case unknown
}

/// Window section shown by an application's native context menu.
nonisolated enum ApplicationWindowMenuState: Equatable, Sendable {
    case hidden
    case loading
    case loaded([ApplicationWindowSummary])
    case unavailable(ApplicationWindowDiscoveryFailure)
}

/// Live application state captured when a context menu opens.
nonisolated struct ApplicationMenuSnapshot: Equatable, Sendable {
    let processes: [ApplicationProcessSnapshot]
    let windowState: ApplicationWindowMenuState
    /// macOS 27 reports the app as running in background. Only true while `processes` is empty.
    var isRunningInBackground = false

    var isRunning: Bool { !processes.isEmpty }
    var allProcessesHidden: Bool { isRunning && processes.allSatisfy(\.isHidden) }
}

/// Commands owned by the application-menu controller rather than launch handling or pin editing.
nonisolated enum ApplicationMenuAction: Equatable, Sendable {
    case showInFinder
    case setHidden(Bool)
    case bringAllToFront
    case quit
    /// Ends the processes a quit app left running. Offered only for background tiles, and silent:
    /// it never produces an error message.
    case stopRunningInBackground
    case selectWindow(ApplicationWindowToken)

    var activatesApplication: Bool {
        switch self {
        case .setHidden(false), .bringAllToFront, .selectWindow: true
        case .showInFinder, .setHidden(true), .quit, .stopRunningInBackground: false
        }
    }
}

/// What one application-menu command did.
nonisolated enum ApplicationMenuOutcome: Sendable {
    case succeeded
    /// The command failed; the dock shows `message`.
    case failed(LocalizedStringResource)
    /// The command did nothing and nothing is shown. Stop Running in Background reports this
    /// when the app is no longer running in background.
    case skipped

    /// The message to show, if any. Only `failed` has one.
    var message: LocalizedStringResource? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Pure projection rules shared by native menu construction and unit tests.
nonisolated enum ApplicationContextMenuProjection {
    static func applicationActions(isAvailable: Bool, snapshot: ApplicationMenuSnapshot) -> [ApplicationMenuAction] {
        var actions: [ApplicationMenuAction] = []
        if isAvailable { actions.append(.showInFinder) }
        if snapshot.isRunning {
            actions.append(.setHidden(!snapshot.allProcessesHidden))
            actions.append(.bringAllToFront)
            actions.append(.quit)
        } else if snapshot.isRunningInBackground {
            // Takes Quit's place, as in the system Dock.
            actions.append(.stopRunningInBackground)
        }
        return actions
    }

    static func windowTitles(_ windows: [ApplicationWindowSummary], untitled: String) -> [String] {
        windows.map { windowTitle($0, untitled: untitled) }
    }

    static func windowTitle(_ window: ApplicationWindowSummary, untitled: String) -> String {
        guard let title = window.title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return untitled }
        return title
    }
}
