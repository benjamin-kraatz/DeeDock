import Foundation

/// Artwork for the menu-bar extra. App-wide, and independent of display docks or Restore Defaults.
enum MenuBarIconStyle: String, CaseIterable, Equatable, Hashable {
    /// The cropped dock mark, sized like other status items.
    case icon
    /// The DDOCK letters. Wider than the icon; still capped for the menu bar.
    case wordmark
}
