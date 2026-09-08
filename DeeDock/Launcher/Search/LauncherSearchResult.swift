import Foundation

/// Object identity includes its kind. A file, app, and capsule with the same name remain separate actions.
nonisolated enum LauncherSearchID: Hashable, Sendable {
    case application(String), window(UUID), capsule(UUID), shelf(UUID), shortcut(UUID), mode(UUID)
}

nonisolated enum LauncherSearchKind: String, CaseIterable, Identifiable, Sendable {
    case all, application, window, capsule, shelf, shortcut, mode
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: .unifiedAll
        case .application: .unifiedApps
        case .window: .unifiedWindows
        case .capsule: .unifiedCapsules
        case .shelf: .unifiedShelf
        case .shortcut: .unifiedShortcuts
        case .mode: .unifiedModes
        }
    }
    var symbol: String {
        switch self {
        case .all: "magnifyingglass"
        case .application: "app"
        case .window: "macwindow"
        case .capsule: "archivebox"
        case .shelf: "doc"
        case .shortcut: "bolt"
        case .mode: "rectangle.3.group"
        }
    }
}

/// A value-only result. Native handles and file leases stay with their existing owners.
nonisolated struct LauncherSearchResult: Identifiable, Sendable {
    let id: LauncherSearchID
    let kind: LauncherSearchKind
    let title: String
    let source: String
    let action: LocalizedStringResource
    let score: Int
    let tieBreak: String
    var application: LauncherApplication?
    var window: WindowSearchSource?
    var unavailable = false
}

/// Copies only searchable metadata, never mode configuration or file contents.
nonisolated struct LauncherSearchName: Equatable, Sendable {
    let id: UUID
    let name: String
}

nonisolated struct LauncherSearchInput: Equatable, Sendable {
    var query: String
    var kind: LauncherSearchKind
    var applications: [LauncherApplication]
    var capsules: [SessionCapsule]
    var shelf: [ShelfItem]
    var shortcuts: [ActionTile]
    var modes: [LauncherSearchName]
    var windowRevision: UUID
}
