import Foundation

/// Stable identity for one chooser row. Hover and keyboard selection never execute it.
nonisolated enum LauncherFileActionID: Hashable, Sendable {
    case openWith(String)
    case shortcut(UUID)
    case copyTo(UUID)
    case chooseFolder
    /// Lookout's Find Similar on the batch's one file, offered by the Hub (`LauncherFileSimilar`).
    case findSimilar
}

/// Find Similar for a batch of one file, which the Hub offers in its Apps tab when Lookout can search with that file:
/// a picture Lookout reads, or a file its index holds. Outside the Hub there's none. Main actor.
struct LauncherFileSimilar {
    /// Whether Lookout can search with the file now. May ask the index, so it's asynchronous.
    let isAvailable: @MainActor (URL) async -> Bool
    /// Starts the search with the file: the Hub switches to the Files tab.
    let run: @MainActor (URL) -> Void
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
