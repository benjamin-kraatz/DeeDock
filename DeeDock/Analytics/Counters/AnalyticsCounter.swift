import Foundation

/// Interactions that happen too often to send one event each.
///
/// They are counted exactly, kept on disk, and sent as properties of the periodic
/// `usage_summary` event. Dock magnification is deliberately absent: it follows every pointer
/// move and its settings already describe how it is used.
enum AnalyticsCounter: Hashable {
    /// A dock label became visible, by pointer or by keyboard selection.
    case tooltipShown(keyboard: Bool)
    /// A hidden dock revealed itself because the pointer entered its activation zone.
    case autoHideReveal(zone: DockBehaviorSettings.ActivationLocation, edge: DockEdge)
    /// A drag hovered a folder or drive tile long enough to spring it open.
    case springLoad(AnalyticsStackKind)
    /// Window Peek staged an enlarged card under a dwelling pointer.
    case peekEnlarge
    /// A dragged drive tile crossed the distance at which releasing it ejects.
    case dragToEjectArmed
    /// An app tile was activated from the dock.
    case appActivated(AnalyticsTrigger)
    /// A soap-bubble burst played.
    case soapBubbleBurst
    /// A collapsed app group was expanded or collapsed by click, keyboard, or VoiceOver.
    case dockGroupToggled(expanded: Bool)
    /// An app badge became news: it appeared, or its count rose past the acknowledged one.
    /// Line icon docks draw this as the red ring; the count is the same for every icon style.
    case badgeNew
    /// A badge that was news was acknowledged, and how.
    case badgeAcknowledged(AnalyticsBadgeAcknowledgement)
    /// The app removed a badge that was still news, before anyone acknowledged it in DOKK.
    case badgeClearedWhileNew
    /// A Line dock label showed a badge's count, with or without the newest banner under it.
    case badgeDetailShown(banner: Bool)

    /// The property name in `usage_summary`.
    var key: String {
        switch self {
        case let .tooltipShown(keyboard): "tooltip_shown_\(keyboard ? "keyboard" : "hover")"
        case let .autoHideReveal(zone, edge): "auto_hide_reveal_\(zone.rawValue)_\(edge.rawValue)"
        case let .springLoad(kind): "spring_load_\(kind.rawValue)"
        case .peekEnlarge: "peek_enlarge"
        case .dragToEjectArmed: "drag_to_eject_armed"
        case let .appActivated(trigger): "app_activated_\(trigger.rawValue)"
        case .soapBubbleBurst: "soap_bubble_burst"
        case let .dockGroupToggled(expanded): expanded ? "dock_group_expanded" : "dock_group_collapsed"
        case .badgeNew: "badge_new"
        case let .badgeAcknowledged(route): "badge_acknowledged_\(route.rawValue)"
        case .badgeClearedWhileNew: "badge_cleared_while_new"
        case let .badgeDetailShown(banner): banner ? "badge_detail_shown_with_banner" : "badge_detail_shown"
        }
    }
}

/// How a badge that was news came to be acknowledged.
enum AnalyticsBadgeAcknowledgement: String {
    /// Its dock tile was clicked.
    case dockClick = "dock_click"
    /// Its app was brought to the front some other way, such as Command-Tab.
    case activation
    /// It arrived while its app was already frontmost.
    case frontmost
}
