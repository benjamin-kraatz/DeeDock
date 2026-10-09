import SwiftUI

/// Where the glass body sits inside the Hub's window, and where its pointer is.
///
/// The window is larger than the glass while anchored (room for the glass's own shadow) and
/// during the detach morph (the union of the start and end frames). Expressing the body as insets
/// from the window's edges lets AppKit own the window frame while SwiftUI animates only the glass.
struct HubBodyLayout: Equatable {
    /// Insets from the window's content bounds to the glass, including the pointer strip.
    var insets: EdgeInsets
    /// The dock edge the pointer faces. Kept while detached so the pointer can fade out in place.
    var edge: DockEdge
    /// Pointer center along the side facing the dock, in the body's top-left space.
    var pointerOffset: CGFloat
    /// Pointer depth; ``HubStyle/pointerSize`` height while anchored, 0 while detached.
    var pointerDepth: CGFloat
    /// Corner radius of the glass body.
    var cornerRadius: CGFloat

    /// A detached window: the glass fills it and has no pointer.
    static let detached = HubBodyLayout(insets: EdgeInsets(), edge: .bottom, pointerOffset: 0, pointerDepth: 0,
                                        cornerRadius: HubStyle.detachedCornerRadius)
}

/// The stages of the open and close transitions.
enum HubPresentationPhase: Equatable {
    /// Before the open animation: smaller, lower, blurred, and transparent.
    case entering
    /// On screen at rest.
    case shown
    /// During the close animation: slightly smaller and fading out.
    case leaving
}

/// Observable presentation state the Hub's SwiftUI views read.
///
/// The ``HubCoordinator`` and ``HubPanelController`` write it on the main actor; views only read
/// it and report focus changes back through ``searchFieldFocused``.
@MainActor @Observable
final class HubShellState {
    /// The visible tab.
    var tab: HubTab
    /// +1 when the last switch moved right in the switcher, -1 when it moved left. Content slides
    /// in from that side.
    private(set) var switchDirection: CGFloat = 1
    /// Whether the Hub is a normal window instead of a panel anchored to its tile.
    var isDetached = false
    /// Placement of the glass inside the window.
    var layout: HubBodyLayout = .detached
    /// Drives the open and close transitions of the glass and its content.
    var phase: HubPresentationPhase = .entering
    /// Incremented to move keyboard focus to the search field.
    private(set) var searchFocusRequest = 0
    /// Whether the latest search-focus request should leave the caret after the text instead of
    /// selecting it all. Type-to-search sets it, so the next keystroke appends rather than replaces.
    private(set) var searchFocusPlacesCaretAtEnd = false
    /// Incremented to take keyboard focus out of the search field.
    private(set) var contentFocusRequest = 0
    /// Mirrors the search field's focus, so key routing can tell the tab where an event came from.
    var searchFieldFocused = false
    /// Read from the workspace when the Hub opens; the open and close transitions depend on it.
    var reduceMotion = false
    /// Read from the workspace when the Hub opens; the glass falls back to an opaque fill.
    var reduceTransparency = false
    /// Incremented by a click on the DOKK tile while the Hub is already open as a window.
    private(set) var tilePulse = 0

    init(tab: HubTab) {
        self.tab = tab
    }

    /// Switches tabs and records the direction for the content transition.
    func select(_ tab: HubTab) {
        guard tab != self.tab else { return }
        let order = HubTab.allCases
        let from = order.firstIndex(of: self.tab) ?? 0
        let to = order.firstIndex(of: tab) ?? 0
        switchDirection = to > from ? 1 : -1
        self.tab = tab
    }

    func requestSearchFocus(caretAtEnd: Bool = false) {
        searchFocusPlacesCaretAtEnd = caretAtEnd
        searchFocusRequest += 1
    }
    func requestContentFocus() { contentFocusRequest += 1 }
    func pulseTile() { tilePulse += 1 }
}

extension HubShellState {
    /// Deterministic state for previews: shown, with the given tab and mode.
    static func preview(tab: HubTab, detached: Bool = false, edge: DockEdge = .bottom,
                        reduceTransparency: Bool = false) -> HubShellState {
        let state = HubShellState(tab: tab)
        state.isDetached = detached
        state.phase = .shown
        state.reduceTransparency = reduceTransparency
        state.layout = detached ? .detached : HubBodyLayout(
            insets: EdgeInsets(), edge: edge, pointerOffset: 180, pointerDepth: HubStyle.pointerSize.height,
            cornerRadius: HubStyle.anchoredCornerRadius)
        return state
    }
}
