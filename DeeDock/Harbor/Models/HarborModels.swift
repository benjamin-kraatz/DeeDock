import CoreGraphics
import Foundation

/// How Harbor can reach a window.
nonisolated enum HarborWindowState: Equatable, Sendable {
    /// On screen in the current Space. Harbor shows a thumbnail card.
    case visible
    /// Minimized to the Dock. Harbor shows a chip; choosing it restores the window.
    case minimized
    /// Belongs to a hidden app. Harbor shows a chip; choosing it unhides the app.
    case hidden
}

/// One window as Harbor shows it. Native Accessibility and ScreenCaptureKit handles stay inside
/// ``HarborWindowService``; this value only names them.
nonisolated struct HarborWindow: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The owning app's ``ApplicationReference/id`` form: bundle identifier, or bundle path.
    let appID: String
    let processIdentifier: pid_t
    let title: String?
    /// Global Quartz bounds in points: origin at the primary display's top-left corner, y down.
    /// AX, ScreenCaptureKit, and `CGWindowList` all report this space.
    let frame: CGRect
    let state: HarborWindowState
    /// Exact Accessibility identity. Nil when Accessibility is off; such a card activates its app.
    let token: ApplicationWindowToken?
    /// Window-server number for the thumbnail. Nil when no single on-screen window matched.
    let captureID: CGWindowID?
    /// Front-to-back order across every window Harbor found; lower is nearer the front.
    let stackOrder: Int
    /// The window's Accessibility document: a file URL for document and Finder windows, a web
    /// URL in browsers. Nil without Accessibility or for windows that have none. Captions show
    /// it as a second line; see ``HarborCaptionText``.
    var document: String? = nil
}

/// A running regular app, captured on the main actor when Harbor opens.
nonisolated struct HarborRunningApp: Equatable, Sendable {
    let id: String
    let name: String
    let processIdentifier: pid_t
    let isHidden: Bool
    let isActive: Bool
}

/// Which window permissions Harbor had when it gathered windows.
nonisolated struct HarborAccess: Equatable, Sendable {
    /// Accessibility: exact window raise and close, minimized windows, hidden-app windows.
    var windows: Bool
    /// Screen Recording: thumbnails and titles without Accessibility.
    var thumbnails: Bool
}

/// Everything one discovery pass found.
nonisolated struct HarborDiscovery: Equatable, Sendable {
    var windows: [HarborWindow]
    var access: HarborAccess
    /// The service session holding these windows' handles; ending it releases them.
    var sessionID: UUID
}

/// An app's windows on one display, in Harbor's order.
nonisolated struct HarborAppGroup: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Visible windows, front to back.
    var windows: [HarborWindow]
    /// Minimized and hidden windows, shown as chips.
    var tucked: [HarborWindow]

    var count: Int { windows.count + tucked.count }
}

/// A running app in Harbor's dock strip.
nonisolated struct HarborStripApp: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let processIdentifier: pid_t
}

/// Projects discovery results into one display's groups.
nonisolated enum HarborGrouping {
    /// Groups the windows whose frames overlap `displayBounds` most, ordered by the frontmost
    /// visible window of each app. Apps with only tucked windows follow, in running-app order.
    ///
    /// - Parameters:
    ///   - windows: Every window Harbor found.
    ///   - apps: Running apps in the order the dock strip shows them.
    ///   - displayBounds: Each candidate display's Quartz bounds, keyed by display ID.
    ///   - displayID: The display to group for.
    static func groups(windows: [HarborWindow], apps: [HarborRunningApp],
                       displayBounds: [String: CGRect], displayID: String) -> [HarborAppGroup] {
        let names = Dictionary(apps.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let mine = windows.filter { display(for: $0.frame, in: displayBounds) == displayID }
        let byApp = Dictionary(grouping: mine, by: \.appID)
        var groups = byApp.map { appID, windows in
            HarborAppGroup(id: appID, name: names[appID] ?? "",
                           windows: windows.filter { $0.state == .visible }.sorted { $0.stackOrder < $1.stackOrder },
                           tucked: windows.filter { $0.state != .visible }.sorted { $0.stackOrder < $1.stackOrder })
        }
        let appOrder = Dictionary(apps.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        groups.sort { first, second in
            let a = first.windows.first?.stackOrder, b = second.windows.first?.stackOrder
            switch (a, b) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (appOrder[first.id] ?? .max) < (appOrder[second.id] ?? .max)
            }
        }
        return groups
    }

    /// The display a window belongs to: the one its frame overlaps most. A window that overlaps
    /// none, such as a minimized window whose frame is off screen, goes to the nearest display.
    static func display(for frame: CGRect, in displays: [String: CGRect]) -> String? {
        let overlaps = displays.map { id, bounds -> (String, CGFloat) in
            let area = frame.intersection(bounds)
            return (id, area.isNull ? 0 : area.width * area.height)
        }
        if let best = overlaps.max(by: { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }), best.1 > 0 {
            return best.0
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.min { first, second in
            distance(center, first.value) < distance(center, second.value)
                || (distance(center, first.value) == distance(center, second.value) && first.key < second.key)
        }?.key
    }

    /// Filters groups by a search query. Every word must occur in the window title or app name,
    /// ignoring case and diacritics. An app-name match keeps all of that app's windows.
    static func filter(_ groups: [HarborAppGroup], query: String) -> [HarborAppGroup] {
        let words = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return groups }
        return groups.compactMap { group in
            let name = normalized(group.name)
            let keep: (HarborWindow) -> Bool = { window in
                let haystack = name + " " + normalized(window.title ?? "")
                return words.allSatisfy(haystack.contains)
            }
            var result = group
            result.windows = group.windows.filter(keep)
            result.tucked = group.tucked.filter(keep)
            return result.count == 0 ? nil : result
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
