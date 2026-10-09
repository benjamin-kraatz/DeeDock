import SwiftUI

/// Sizes from the approved mockup (`docs/mockups/dokk-hub.html`, Files section).
enum HubFilesMetrics {
    static let tabStripHeight: CGFloat = 40
    static let tabHeight: CGFloat = 36
    static let sidebarWidth: CGFloat = 200
    static let navigationBarHeight: CGFloat = 42
    static let listHeaderHeight: CGFloat = 28
    static let rowHeight: CGFloat = 32
    static let previewWidth: CGFloat = 272
    static let previewWellHeight: CGFloat = 250
    static let statusBarHeight: CGFloat = 46
    static let tileIconSize: CGFloat = 54
    static let tileMinimumWidth: CGFloat = 96
    static let columnWidth: CGFloat = 200
    static let columnRowHeight: CGFloat = 28
    static let modifiedColumnWidth: CGFloat = 118
    static let kindColumnWidth: CGFloat = 104
    static let sizeColumnWidth: CGFloat = 62
    static let whereColumnWidth: CGFloat = 200
}

/// Fills and strokes from the mockup's light and dark variables.
///
/// Translucent tints over the Hub's glass, so the material shows through as in the mockup.
struct HubFilesTheme {
    let scheme: ColorScheme

    init(_ scheme: ColorScheme) { self.scheme = scheme }

    private var isDark: Bool { scheme == .dark }
    private var ink: Color { isDark ? .white : .black }

    /// Hover fill.
    var chip: Color { ink.opacity(isDark ? 0.07 : 0.05) }
    /// Pressed or "on" fill for small controls.
    var chipHighlight: Color { ink.opacity(isDark ? 0.12 : 0.09) }
    /// Selection in an inactive pane; the active tab and sidebar row.
    var selection: Color { ink.opacity(isDark ? 0.09 : 0.065) }
    /// Selection in the active pane and drop-target fill.
    var accentSelection: Color { Color.accentColor.opacity(isDark ? 0.30 : 0.17) }
    /// Inner stroke of accent selections and drop targets.
    var accentLine: Color { Color.accentColor.opacity(isDark ? 0.55 : 0.42) }
    /// Hairline separators.
    var line: Color { ink.opacity(isDark ? 0.08 : 0.075) }
    /// Sidebar backdrop over the panel material.
    var sidebar: Color { isDark ? Color.black.opacity(0.10) : Color.white.opacity(0.22) }
    /// Preview well.
    var well: Color { isDark ? Color.black.opacity(0.16) : Color.white.opacity(0.35) }
    /// The green of a freshly arrived item and the completed-transfer check.
    var fresh: Color { Color(red: 0.19, green: 0.82, blue: 0.35) }
}

/// Motion helpers that respect Reduce Motion, read the way the rest of DOKK reads it.
enum HubFilesMotion {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// `animation`, or nil under Reduce Motion so changes apply instantly.
    static func animation(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Small, quick state changes: hover, selection.
    static var quick: Animation? { animation(.easeOut(duration: 0.12)) }
    /// Layout changes: split, preview column, tabs. The Hub's shared spring.
    static var layout: Animation? { animation(HubStyle.motion) }
}
