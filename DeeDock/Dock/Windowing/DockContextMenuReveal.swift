import Foundation

/// How a dock tile gets out from under its own context menu. App-wide, in Settings > Features.
///
/// A context menu opens over the tile, and the menu window always draws above the dock, so a
/// tile moving out from its slot is hidden for most of the trip. Each style handles that
/// differently. Reduce Motion plays every moving style as an in-place fade.
enum DockContextMenuReveal: String, Codable, CaseIterable, Identifiable {
    /// The menu opens at once. The tile leaves its covered slot instantly and pops in beside the
    /// menu, so the part you can see is the arrival.
    case popOut
    /// The tile slides clear first and the menu opens a moment later, so the whole slide is visible.
    case slideOut
    /// The tile stays in its slot; the rest of the dock still dims.
    case off

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .popOut: .contextMenuRevealPopOut
        case .slideOut: .contextMenuRevealSlideOut
        case .off: .contextMenuRevealOff
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .popOut: .contextMenuRevealPopOutHelp
        case .slideOut: .contextMenuRevealSlideOutHelp
        case .off: .contextMenuRevealOffHelp
        }
    }

    /// The style actually played. Reduce Motion keeps the tile clear of the menu, which a still
    /// tile could not be, but arrives without travel, which only Pop Out offers.
    func effective(reduceMotion: Bool) -> Self {
        reduceMotion && self == .slideOut ? .popOut : self
    }

    /// How long Slide Out holds the menu back. The slide springs with
    /// ``DockContextMenuSpotlight`` timing and has covered most of its distance by then.
    static let slideLead: TimeInterval = 0.16
}
