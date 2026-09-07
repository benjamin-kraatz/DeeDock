import SwiftUI

/// Shared metrics and symbols for the search presentation.
///
/// Keeping them in one place lets the header, the result rows, and the capture picker stay on the
/// same rhythm without each view inventing its own numbers.
enum WindowSearchStyle {
    static let contentPadding: CGFloat = 16
    static let rowCorner: CGFloat = 10
    static let thumbnailSize = CGSize(width: 104, height: 64)
    static let minimumSize = CGSize(width: 640, height: 560)
}

extension WindowSearchScope {
    /// What the scope searches, including whether capture or a model is involved.
    var help: LocalizedStringResource {
        switch self {
        case .live: .windowSearchLiveHelp
        case .captured: .windowSearchRetention
        case .saved: .windowSearchSavedHelp
        }
    }

    /// Sidebar-free scopes still need a glyph so the segmented control reads at a glance.
    var symbol: String {
        switch self {
        case .live: "macwindow"
        case .captured: "text.viewfinder"
        case .saved: "archivebox"
        }
    }
}

extension WindowSearchEvidence {
    var symbol: String {
        switch self {
        case .metadata: "textformat"
        case .text: "text.viewfinder"
        case .capsule: "archivebox"
        case .image: "sparkles"
        }
    }

    /// Image matches are model suggestions, so they are tinted apart from literal evidence.
    var tint: Color {
        switch self {
        case .image: .orange
        default: .secondary
        }
    }
}

/// How prominently a status message should be presented.
///
/// `WindowSearchState` publishes one localized message for every outcome. Matching the resolved
/// string keeps the presentation decision in the view layer without widening the state's API.
enum WindowSearchNoticeKind {
    case info, caution, failure

    init(_ message: LocalizedStringResource) {
        let text = String(localized: message)
        if Self.failures.contains(text) { self = .failure }
        else if text == String(localized: .windowSearchImageCaution) { self = .caution }
        else { self = .info }
    }

    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .caution: "exclamationmark.triangle"
        case .failure: "exclamationmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info: .secondary
        case .caution: .orange
        case .failure: .red
        }
    }

    private static let failures: Set<String> = [
        String(localized: .windowSearchUnavailable),
        String(localized: .windowSearchCaptureUnavailable),
        String(localized: .windowSearchModelUnavailable),
        String(localized: .windowSearchStale),
        String(localized: .windowSearchTimedOut),
        String(localized: .windowSearchDeleteFailed),
        String(localized: .windowSearchExpired),
    ]
}
