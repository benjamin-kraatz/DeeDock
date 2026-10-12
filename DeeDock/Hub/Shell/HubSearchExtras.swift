import AppKit
import UniformTypeIdentifiers

/// A token in the header search field before the text: the Files tab's picture to search with.
struct HubSearchToken: Equatable, Identifiable {
    let id: UUID
    /// The name it shows, as the file is called (never localized), or a localized "Pasted picture".
    let title: String
    /// A file to draw a thumbnail of, through Quick Look.
    let fileURL: URL?
    /// A picture to draw instead (pasted pixels), when there's no file.
    let image: NSImage?
    /// VoiceOver's name for the token ("Picture: IMG_4821.HEIC").
    let accessibilityLabel: String

    static func == (lhs: HubSearchToken, rhs: HubSearchToken) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.fileURL == rhs.fileURL
    }
}

/// What the header search field shows while something is dragged over the Hub.
enum HubSearchDropState: Equatable {
    /// No drag, or one the visible tab ignores: the field as usual.
    case none
    /// The field widens into a drop well that takes the drag, with what dropping does.
    case accepting(message: String)
    /// The field widens and says why it won't take the drag.
    case refusing(message: String)

    var isShown: Bool { self != .none }
}

/// What a tab adds to the header search field beyond its text: a token before the text, a drop well while something
/// is dragged over the Hub, and what dropping on the field does. The Files tab provides it for searching with a
/// picture; the other tabs don't (`HubTabModel.searchExtras` is nil).
///
/// Drags are observed, never taken over: the observer over the Hub refuses every drop it sees (`dragOperation`
/// returns none outside the field), so a drop anywhere but on the field behaves exactly as it did. Main actor.
@MainActor protocol HubSearchExtras: AnyObject {
    /// The token in the field, or nil.
    var searchToken: HubSearchToken? { get }
    /// The field's placeholder while the token shows (it reads as the field's VoiceOver label).
    var searchTokenPrompt: LocalizedStringResource { get }
    /// The drop well's state while a drag is over the Hub.
    var searchDropState: HubSearchDropState { get }
    /// True while a drag the field accepts is right over it.
    var isSearchDropTargeted: Bool { get }
    /// The pasteboard types the Hub watches drags of, and the field takes.
    var searchDropTypes: [UTType] { get }

    /// ✕ on the token.
    func removeSearchToken()
    /// The field's clear button while a token shows: the token and the text go.
    func clearSearchWithToken()

    /// A drag of `searchDropTypes` entered (true) or left (false) the Hub, outside any region that handles drags
    /// itself. Reads the drag pasteboard to decide `searchDropState`.
    func hubDragChanged(inside: Bool)
    /// A drag moved over (true) or off (false) the field.
    func searchFieldDragTargeted(_ targeted: Bool)
    /// Whether the field takes the current drag.
    var searchFieldAcceptsDrag: Bool { get }
    /// The drag was dropped on the field.
    ///
    /// - Returns: Whether it was taken.
    func searchFieldPerformDrop() -> Bool
}
