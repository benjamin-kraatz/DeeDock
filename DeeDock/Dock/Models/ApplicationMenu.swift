import Foundation

/// Current authorization state for reading and controlling another application's windows.
enum WindowAccessStatus: Equatable, Sendable {
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
    let title: String?
    let isMinimized: Bool
    let isMain: Bool

    var id: ApplicationWindowToken { token }
}

/// Window section shown by an application's native context menu.
nonisolated enum ApplicationWindowMenuState: Equatable, Sendable {
    case hidden
    case loading
    case loaded([ApplicationWindowSummary])
    case unavailable
}

/// Live application state captured when a context menu opens.
nonisolated struct ApplicationMenuSnapshot: Equatable, Sendable {
    let processes: [ApplicationProcessSnapshot]
    let windowState: ApplicationWindowMenuState

    var isRunning: Bool { !processes.isEmpty }
    var allProcessesHidden: Bool { isRunning && processes.allSatisfy(\.isHidden) }
}

/// Commands owned by the application-menu controller rather than launch handling or pin editing.
nonisolated enum ApplicationMenuAction: Equatable, Sendable {
    case showInFinder
    case setHidden(Bool)
    case bringAllToFront
    case quit
    case selectWindow(ApplicationWindowToken)

    var activatesApplication: Bool {
        switch self {
        case .setHidden(false), .bringAllToFront, .selectWindow: true
        case .showInFinder, .setHidden(true), .quit: false
        }
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
