import AppKit
import Observation

/// One display's share of an open Harbor.
struct HarborDisplayContent {
    let displayID: String
    /// The display's size in points; Harbor's panel covers all of it.
    let size: CGSize
    /// Top-left corner of the display in global Quartz coordinates. Subtracting it turns a
    /// window frame into the panel's top-left, y-down space.
    let quartzOrigin: CGPoint
    /// The display's DOKK dock edge. The strip of running apps sits there.
    let stripEdge: DockEdge
    /// Blurred wallpaper, or nil for the plain backdrop.
    var wallpaper: CGImage?
    /// Every group on this display, before search and app filtering.
    var groups: [HarborAppGroup]
    /// Running apps in dock order, for the strip.
    var stripApps: [HarborStripApp]
    /// The dock as it was drawn when Harbor opened, or nil when it was hidden; the strip
    /// transforms from it and back into it.
    var dockSeed: HarborDockSeed? = nil
    /// Groups after search and app filtering, in layout order.
    var shownGroups: [HarborAppGroup] = []
    var layout = HarborLayoutResult()

    /// Where a window currently sits on the desktop, in this panel's coordinates.
    func desktopFrame(of window: HarborWindow) -> CGRect {
        window.frame.offsetBy(dx: -quartzOrigin.x, dy: -quartzOrigin.y)
    }

    /// The area groups may use, leaving room for the search field, notices, and the strip.
    ///
    /// The header sits 20 points from the top, or under the strip on a top dock; groups start
    /// 22 points below the search field. The strip's side keeps its usual margin past the strip.
    func layoutBounds(showsSearch: Bool, showsNotice: Bool) -> CGRect {
        let top = HarborStripMetrics.headerTop(edge: stripEdge) + (showsSearch ? 58 + (showsNotice ? 50 : 0) : 28)
        var rect = CGRect(x: 56, y: top, width: size.width - 112, height: size.height - top - 40)
        let reserve = HarborStripMetrics.thickness + HarborStripMetrics.edgeInset
        switch stripEdge {
        case .bottom: rect.size.height -= reserve
        case .top: break
        case .left: rect.origin.x += reserve; rect.size.width -= reserve
        case .right: rect.size.width -= reserve
        }
        return rect
    }
}

/// Size of the running-apps strip, shared by its view and the layout reservation.
nonisolated enum HarborStripMetrics {
    /// Depth of the strip across its edge, with app names under the icons.
    static let thickness: CGFloat = 92
    static let edgeInset: CGFloat = 8

    /// Where the search field starts: near the top, or below the strip when the dock is there.
    static func headerTop(edge: DockEdge) -> CGFloat {
        if case .top = edge {
            return HarborStripLayout.Metrics.edgeInset + HarborStripLayout.Metrics.menuBarAllowance + thickness + 16
        }
        return 20
    }
}

/// Observable state for one Harbor presentation, shared by every display's panel.
///
/// The coordinator owns the lifecycle; views read this and send intents back through it.
/// All mutation happens on the main actor.
@MainActor @Observable
final class HarborSession {
    enum Phase: Equatable {
        /// Nothing on screen.
        case hidden
        /// Panels are up with windows at their desktop frames, about to fly out.
        case entering
        /// Windows sit in the grid.
        case open
        /// Windows are flying back; the panels close when the animation ends.
        case leaving
    }

    private(set) var phase: Phase = .hidden
    /// Whether the backdrop covers the desktop and the strip has left the dock's shape. Turned on
    /// a frame after the panels appear, so both animate in, and off again as the windows fly home.
    private(set) var showsBackdrop = false
    private(set) var displays: [String: HarborDisplayContent] = [:]
    private(set) var thumbnails: [UUID: CGImage] = [:]
    /// Windows that leave from and return to their desktop frame. The rest fade in place,
    /// because without a thumbnail a card flying from the window would not match it.
    private(set) var flying: Set<UUID> = []
    /// The display whose panel holds the search field and keyboard focus.
    private(set) var keyDisplayID: String?
    private(set) var access = HarborAccess(windows: false, thumbnails: false)
    /// App icons by app ID, read on the main actor when Harbor opened.
    private(set) var icons: [String: NSImage] = [:]
    /// The window being raised as Harbor closes; it flies above the rest.
    private(set) var raisedWindowID: UUID?
    var query = "" {
        didSet { if query != oldValue { selected = nil; relayout() } }
    }
    /// Shows only this app's group, after a click on its strip tile.
    private(set) var appFilter: String?
    var hovered: UUID?
    var selected: UUID?
    /// Captured when Harbor opens, so a settings change mid-animation cannot mix styles.
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false

    var isPresented: Bool { phase != .hidden }
    var showsGrid: Bool { phase == .open }

    /// Starts a presentation with gathered content. Panels show windows at their desktop frames.
    func begin(displays: [String: HarborDisplayContent], keyDisplayID: String?, access: HarborAccess,
               icons: [String: NSImage], reduceMotion: Bool, reduceTransparency: Bool) {
        self.displays = displays
        self.keyDisplayID = keyDisplayID
        self.access = access
        self.icons = icons
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        query = ""
        appFilter = nil
        hovered = nil
        selected = nil
        raisedWindowID = nil
        showsBackdrop = false
        relayout()
        phase = .entering
    }

    /// Dims the desktop and starts the dock's transformation, ahead of the windows' flight.
    func showBackdrop() { showsBackdrop = true }

    /// Records which windows had a thumbnail in time to fly, then opens the grid.
    func reveal() {
        flying = reduceMotion ? [] : Set(thumbnails.keys)
        showsBackdrop = true
        phase = .open
    }

    func setThumbnail(_ image: CGImage, for id: UUID) { thumbnails[id] = image }

    func setWallpaper(_ image: CGImage?, for displayID: String) { displays[displayID]?.wallpaper = image }

    /// Starts the return flight. `raising` flies above the others.
    func leave(raising id: UUID?) {
        raisedWindowID = id
        hovered = nil
        selected = nil
        showsBackdrop = false
        phase = .leaving
    }

    func end() {
        phase = .hidden
        showsBackdrop = false
        displays = [:]
        thumbnails = [:]
        flying = []
        icons = [:]
        query = ""
        appFilter = nil
        hovered = nil
        selected = nil
        raisedWindowID = nil
    }

    /// Toggles the strip filter for one app.
    func toggleFilter(_ appID: String) {
        appFilter = appFilter == appID ? nil : appID
        selected = nil
        relayout()
    }

    func clearFilter() {
        guard appFilter != nil else { return }
        appFilter = nil
        relayout()
    }

    /// Removes a closed window and reflows its display.
    func remove(_ id: UUID) {
        for key in displays.keys {
            displays[key]?.groups = displays[key]!.groups.compactMap { group in
                var group = group
                group.windows.removeAll { $0.id == id }
                group.tucked.removeAll { $0.id == id }
                return group.count == 0 ? nil : group
            }
        }
        thumbnails[id] = nil
        if hovered == id { hovered = nil }
        if selected == id { selected = nil }
        relayout()
    }

    func window(_ id: UUID) -> HarborWindow? {
        for content in displays.values {
            for group in content.groups {
                if let window = group.windows.first(where: { $0.id == id }) ?? group.tucked.first(where: { $0.id == id }) {
                    return window
                }
            }
        }
        return nil
    }

    /// The display and app of the group that holds the pointer or keyboard selection.
    var highlightedAppID: String? {
        guard showsGrid, let id = hovered ?? selected else { return nil }
        return window(id)?.appID
    }

    /// Visible windows in reading order on the key display, for keyboard navigation.
    var keyboardOrder: [UUID] {
        guard let id = keyDisplayID, let content = displays[id] else { return [] }
        return content.shownGroups.flatMap { $0.windows.map(\.id) }
    }

    /// Moves the keyboard selection to the nearest window in a direction on the key display.
    func moveSelection(_ direction: HarborDirection) {
        guard let id = keyDisplayID, let layout = displays[id]?.layout else { return }
        let order = keyboardOrder
        guard let current = selected ?? hovered, let origin = layout.windows[current] else {
            selected = order.first
            return
        }
        hovered = nil
        selected = HarborNavigation.next(from: origin, direction: direction,
                                          candidates: order.compactMap { id in layout.windows[id].map { (id, $0) } }
                                            .filter { $0.0 != current }) ?? current
    }

    /// Recomputes filtering and layout for every display.
    func relayout() {
        for key in displays.keys {
            guard var content = displays[key] else { continue }
            var groups = HarborGrouping.filter(content.groups, query: query)
            if let appFilter { groups = groups.filter { $0.id == appFilter } }
            let front = query.isEmpty && appFilter == nil && groups.count > 1 && !(groups.first?.windows.isEmpty ?? true)
            content.shownGroups = groups
            let bounds = content.layoutBounds(showsSearch: key == keyDisplayID,
                                              showsNotice: key == keyDisplayID && !access.windows)
            content.layout = HarborLayout.place(groups.enumerated().map { index, group in
                HarborLayoutGroup(id: group.id,
                                  windows: group.windows.map { .init(id: $0.id, aspect: $0.frame.width / max($0.frame.height, 1)) },
                                  chips: group.tucked.map { .init(id: $0.id, width: HarborTextMeasure.chipWidth($0, appName: group.name)) },
                                  headerWidth: HarborTextMeasure.headerWidth(name: group.name, count: group.count),
                                  isFront: front && index == 0)
            }, in: bounds)
            displays[key] = content
        }
    }
}

/// Arrow-key directions for window selection.
nonisolated enum HarborDirection: Sendable { case left, right, up, down }

/// Picks the next window for an arrow key. Pure, for tests.
nonisolated enum HarborNavigation {
    /// The candidate whose center lies in `direction` from `origin`, preferring the nearest along
    /// that axis and penalizing sideways drift.
    static func next(from origin: CGRect, direction: HarborDirection, candidates: [(UUID, CGRect)]) -> UUID? {
        let center = CGPoint(x: origin.midX, y: origin.midY)
        var best: (UUID, CGFloat)?
        for (id, rect) in candidates {
            let dx = rect.midX - center.x, dy = rect.midY - center.y
            let (along, across): (CGFloat, CGFloat) = switch direction {
            case .right: (dx, dy)
            case .left: (-dx, dy)
            case .down: (dy, dx)
            case .up: (-dy, dx)
            }
            guard along > 4 else { continue }
            let score = along + 2.5 * abs(across)
            if best == nil || score < best!.1 { best = (id, score) }
        }
        return best?.0
    }
}

/// Text widths the layout reserves, measured with the fonts the views draw.
@MainActor
enum HarborTextMeasure {
    static func headerWidth(name: String, count: Int) -> CGFloat {
        let nameWidth = width(name, NSFont.systemFont(ofSize: 16, weight: .semibold))
        let countWidth = width("· " + String(localized: .harborWindowCount(count)), NSFont.systemFont(ofSize: 14))
        return 26 + 9 + nameWidth + 9 + countWidth + 4
    }

    static func chipWidth(_ window: HarborWindow, appName: String) -> CGFloat {
        let title = window.title ?? appName
        let state = String(localized: window.state == .minimized ? .harborMinimized : .harborHidden)
        let font = NSFont.systemFont(ofSize: 12)
        return min(280, 6 + 18 + 6 + width(title, font) + 6 + width("· " + state, font) + 12)
    }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
