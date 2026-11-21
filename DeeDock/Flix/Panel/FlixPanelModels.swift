import Foundation

/// How the panel was opened, which decides where it sits.
enum FlixPanelMode: Equatable {
    /// Above (or beside) the dock tile that was clicked.
    case anchored
    /// At the pointer, from the shortcut or the menu bar.
    case pointer
}

/// The panel's open and close pose, animated by the content.
enum FlixPanelPhase: Equatable {
    case entering, shown, leaving
}

/// A sheet over the panel's list.
enum FlixSheet: Identifiable, Equatable {
    case tidy
    case smartFilter
    /// Ask Robi about these items.
    case askRobi([FlixItem.ID])
    /// Rename one item, prefilled with a suggestion when there is one.
    case rename(FlixItem.ID)

    var id: String {
        switch self {
        case .tidy: "tidy"
        case .smartFilter: "smart"
        case .askRobi: "robi"
        case .rename(let id): "rename:\(id)"
        }
    }
}

/// The footer toast, with an optional Undo.
struct FlixToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// A question waiting for an answer before items leave for another app.
struct FlixPendingConfirmation: Identifiable, Equatable {
    let id = UUID()
    let confirmation: FlixDropConfirmation
    /// The items the drag was about to carry.
    let itemIDs: [FlixItem.ID]
}

/// A drag in progress out of the panel.
struct FlixDragActivity: Equatable {
    let itemIDs: [FlixItem.ID]
    /// The pointer left the panel, which faded aside.
    var isOutside = false
}
