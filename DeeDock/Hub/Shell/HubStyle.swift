import SwiftUI

/// Visual constants shared by the Hub shell and its tabs, taken from the approved mockup
/// (`docs/mockups/dokk-hub.html`).
enum HubStyle {
    /// Size of the anchored panel before it is clamped to the display's visible frame.
    static let anchoredSize = CGSize(width: 1180, height: 640)
    /// Smallest size a detached Hub window can be resized to.
    static let minimumDetachedSize = CGSize(width: 900, height: 500)
    /// Gap between the dock tile's top edge and the pointer's tip.
    static let anchorGap: CGFloat = 13
    /// Distance kept between the panel and the visible frame's edges.
    static let screenMargin: CGFloat = 16
    /// The pointer under an anchored panel.
    static let pointerSize = CGSize(width: 24, height: 11)

    static let anchoredCornerRadius: CGFloat = 22
    static let detachedCornerRadius: CGFloat = 16
    static let headerHeight: CGFloat = 58
    static let tabSwitcherItemWidth: CGFloat = 118
    static let searchFieldWidth: CGFloat = 300

    /// Corner radius for rows, tiles, and sidebar items.
    static let rowRadius: CGFloat = 9
    /// Corner radius for cards (suggestions, window groups, preview well).
    static let cardRadius: CGFloat = 16

    /// Open, tab pill, detach/attach, and reflow spring. Matches Radar's motion.
    static let springResponse: Double = 0.37
    static let springDamping: Double = 0.89
    static var motion: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
    /// Hover lift on tiles and cards.
    static var hover: Animation { .spring(response: 0.28, dampingFraction: 0.78) }
    /// Content cross-fade when switching tabs; content slides 18 pt in the switch direction.
    static var tabContent: Animation { .spring(response: 0.3, dampingFraction: 0.9) }
    static let tabContentOffset: CGFloat = 18
    /// Close: quick ease-in, 0.17 s, scaling to 0.94 toward the pointer.
    static let closeDuration: TimeInterval = 0.17
    /// Open: starts at this scale, 14 pt lower, blurred 6 pt, and springs to identity.
    static let openStartScale: CGFloat = 0.9
}
