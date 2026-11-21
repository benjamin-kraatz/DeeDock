import CoreGraphics
import Foundation

/// Which system picker another app shows: `NSOpenPanel` (`open-panel`) or `NSSavePanel`
/// (`save-panel`).
nonisolated enum FlixPickPickerKind: String, Sendable {
    case open, save

    /// The `AXIdentifier` macOS gives the picker's window or sheet.
    var identifier: String {
        switch self {
        case .open: "open-panel"
        case .save: "save-panel"
        }
    }

    init?(identifier: String?) {
        switch identifier {
        case "open-panel": self = .open
        case "save-panel": self = .save
        default: return nil
        }
    }
}

/// One picker as the Accessibility thread last read it. A value snapshot: the elements themselves
/// never leave that thread (`FlixPickSession`).
///
/// Frames are in Accessibility's global space: points, origin at the top-left of the primary
/// display, y growing downward. Convert with ``FlixPickPlacement/appKitRect(fromAX:primaryMaxY:)``.
nonisolated struct FlixPickPicker: Equatable, Sendable {
    /// Increments for every new picker element; operations and events name the picker by it.
    var serial: Int
    var processIdentifier: pid_t
    var kind: FlixPickPickerKind
    /// A sheet on a document window rather than a window of its own.
    var isSheet: Bool
    var frame: CGRect
    /// The default button's title as the app shows it ("Open", "Import", "Save"); nil until read.
    var buttonTitle: String?
    /// `OKButton` was found, so ⌥-click and double-click can press it.
    var canConfirm: Bool
    /// The list view (`ListView`) was found, so a listed file can be selected in place and a
    /// selection can be read back to verify a jump. Without it, confirming is never attempted.
    var hasListView: Bool
    /// Where `OKButton`, `CancelButton`, and the file list (list or column view) are, for telling
    /// a confirm from a cancel by where the mouse was pressed. Same space as ``frame``.
    var confirmFrame: CGRect?
    var cancelFrame: CGRect?
    var listFrame: CGRect?

    /// Which control an Accessibility point is on.
    func target(at point: CGPoint) -> FlixPickPressTarget {
        if confirmFrame?.contains(point) == true { return .confirm }
        if cancelFrame?.contains(point) == true { return .cancel }
        if listFrame?.contains(point) == true { return .list }
        return .other
    }
}

/// What the Accessibility thread reports to the main actor, in order.
nonisolated enum FlixPickEvent: Sendable {
    /// A picker has focus in the frontmost app. `returning` is true when it is the same picker
    /// element as one reported before (focus came back to it), so it is not counted as shown again.
    case appeared(FlixPickPicker, returning: Bool)
    /// The picker moved, resized, or its default button's title was read.
    case changed(FlixPickPicker)
    /// The list's selection changed; the selected row's file, when one is selected.
    case selection(serial: Int, url: URL?)
    /// The picker's current folder changed: the `where popup` shows a new name.
    case folderChanged(serial: Int, name: String?)
    /// The picker went away. `destroyed` is false when it only lost focus or its app moved to the
    /// back, so it may come back as `appeared(_, returning: true)`.
    case closed(serial: Int, destroyed: Bool)
}

/// Where in the picker a mouse press landed, for telling a confirm from a cancel when it closes.
nonisolated enum FlixPickPressTarget: Sendable {
    case confirm, cancel, list, other
}

/// What a click on a Flix Pick row asked for.
nonisolated enum FlixPickTrigger: Sendable {
    case click, optionClick, doubleClick, drag, accessibility
}

/// Why a row is suggested, as one coloured line under its name.
nonisolated struct FlixPickReason: Equatable, Sendable {
    /// The line's colour: context purple, used before the accent colour, new orange, learned green.
    nonisolated enum Tone: Sendable { case context, used, new, learned }

    var text: String
    var tone: Tone
}

/// One suggestion as the panel draws it.
nonisolated struct FlixPickRow: Identifiable, Equatable, Sendable {
    /// The file or folder. Folders and files picked before that Flix Files does not list are built
    /// for the row and exist only in it.
    var item: FlixItem
    var reason: FlixPickReason
    /// Where it is: "Documents › Oak & Ash".
    var location: String
    /// The trailing time: the item's latest activity, or the last pick.
    var date: Date

    var id: FlixItem.ID { item.id }
    var path: String { item.path ?? "" }
}
