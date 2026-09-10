import Foundation

/// Stable identity for one chooser row. Hover and keyboard selection never execute it.
nonisolated enum LauncherFileActionID: Hashable, Sendable {
    case openWith(String)
    case shortcut(UUID)
    case copyTo(UUID)
    case chooseFolder
}

/// One suitable or searchable action for the current file batch.
nonisolated struct LauncherFileActionItem: Identifiable, Sendable {
    let id: LauncherFileActionID
    let title: String
    let subtitle: LocalizedStringResource
    let symbol: String
    let support: LauncherFileSupport
    /// Display names that this action does not declare support for, in batch order.
    let unsupportedNames: [String]
    let unavailable: Bool
    /// Sort: all-compatible apps, then mixed, then shortcuts, then folders, then unknown/none.
    let rank: Int
    let application: LauncherApplication?
}

/// Restricts the chooser without leaving file-action mode.
nonisolated enum LauncherFileActionKind: String, CaseIterable, Identifiable, Sendable {
    case all, application, shortcut, folder
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: .launcherFileKindAll
        case .application: .launcherFileKindApps
        case .shortcut: .launcherFileKindShortcuts
        case .folder: .launcherFileKindFolders
        }
    }
}

/// Outcome of one deliberate activation. Shortcut rows also read `ActionTileStatus`.
enum LauncherFileOperationStatus: Equatable {
    case idle
    case pending
    case completed
    case failed(String)
    case partial(String)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}
