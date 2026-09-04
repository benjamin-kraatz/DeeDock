import CoreGraphics
import Foundation

/// Persisted thumbnail dimensions. Values are logical points; capture requests use backing pixels.
nonisolated enum WindowPeekSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    var thumbnailSize: CGSize {
        switch self {
        case .small: CGSize(width: 160, height: 100)
        case .medium: CGSize(width: 240, height: 150)
        case .large: CGSize(width: 320, height: 200)
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .small: .windowPeekSizeSmall
        case .medium: .windowPeekSizeMedium
        case .large: .windowPeekSizeLarge
        }
    }
}

/// Arrangement used when a Peek contains more than one window.
nonisolated enum WindowPeekLayout: String, Codable, CaseIterable, Sendable {
    case list, grid, filmstrip

    var title: LocalizedStringResource {
        switch self {
        case .list: .windowPeekLayoutList
        case .grid: .windowPeekLayoutGrid
        case .filmstrip: .windowPeekLayoutFilmstrip
        }
    }
}

/// Visual treatment for each preview card, independent of its arrangement.
nonisolated enum WindowPeekStyle: String, Codable, CaseIterable, Sendable {
    case glass, minimal, captioned

    var title: LocalizedStringResource {
        switch self {
        case .glass: .windowPeekStyleGlass
        case .minimal: .windowPeekStyleMinimal
        case .captioned: .windowPeekStyleCaptioned
        }
    }
}

/// Named combinations are projections over the independently stored settings.
enum WindowPeekPreset: String, CaseIterable, Identifiable, Sendable {
    case compact, balanced, showcase

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .compact: .windowPeekPresetCompact
        case .balanced: .windowPeekPresetBalanced
        case .showcase: .windowPeekPresetShowcase
        }
    }

    func apply(to settings: inout DockSettings) {
        settings.windowPeekEnabled = true
        switch self {
        case .compact:
            settings.windowPeekSize = .small
            settings.windowPeekLayout = .list
            settings.windowPeekStyle = .minimal
            settings.windowPeekIncludeMinimized = false
            settings.windowPeekIncludeUntitled = false
            settings.windowPeekHoverDelay = 0.5
        case .balanced:
            settings.windowPeekSize = .medium
            settings.windowPeekLayout = .grid
            settings.windowPeekStyle = .glass
            settings.windowPeekIncludeMinimized = true
            settings.windowPeekIncludeUntitled = true
            settings.windowPeekHoverDelay = 0.4
        case .showcase:
            settings.windowPeekSize = .large
            settings.windowPeekLayout = .filmstrip
            settings.windowPeekStyle = .captioned
            settings.windowPeekIncludeMinimized = true
            settings.windowPeekIncludeUntitled = true
            settings.windowPeekHoverDelay = 0.3
        }
    }

    static func matching(_ settings: DockSettings) -> Self? {
        allCases.first { preset in
            var candidate = settings
            preset.apply(to: &candidate)
            return candidate.windowPeekEnabled == settings.windowPeekEnabled
                && candidate.windowPeekSize == settings.windowPeekSize
                && candidate.windowPeekLayout == settings.windowPeekLayout
                && candidate.windowPeekStyle == settings.windowPeekStyle
                && candidate.windowPeekIncludeMinimized == settings.windowPeekIncludeMinimized
                && candidate.windowPeekIncludeUntitled == settings.windowPeekIncludeUntitled
                && candidate.windowPeekHoverDelay == settings.windowPeekHoverDelay
        }
    }
}
