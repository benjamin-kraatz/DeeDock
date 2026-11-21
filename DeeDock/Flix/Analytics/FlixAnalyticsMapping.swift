import Carbon
import Foundation

// Turns Flix Files' own models into the closed analytics vocabulary in
// `AnalyticsFlixEventTypes.swift`. Everything here runs on the Mac and keeps only a category, a
// type, or a count: names, paths, addresses, and text stay behind.

extension FlixItem {
    /// The item's kind for analytics: its file type, reduced to a system type, or folder, app, link.
    nonisolated var analyticsKind: AnalyticsFlixItemKind? {
        switch kind {
        case .folder: return .folder
        case .app: return .app
        case .link: return .link
        default:
            if let type = contentType.flatMap(AnalyticsFileType.init) { return AnalyticsFlixItemKind(file: type) }
            return url.flatMap(AnalyticsFileType.init(url:)).map { AnalyticsFlixItemKind(file: $0) }
        }
    }

    /// What last happened to the item. A file kept by dropping it on Flix Files counts as saved.
    nonisolated var analyticsEvent: AnalyticsFlixItemEvent {
        if kind == .app { return .app }
        switch activity {
        case .opened: return .opened
        case .downloaded: return .downloaded
        case .created: return .new
        case .saved, .kept: return .saved
        case .link: return .link
        }
    }

    /// Whole minutes since the item's latest activity.
    nonisolated func ageMinutes(now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }
}

extension Array where Element == FlixItem {
    /// The kinds in this selection, deduplicated in order.
    nonisolated var analyticsKinds: [AnalyticsFlixItemKind] {
        var kinds: [AnalyticsFlixItemKind] = []
        for kind in compactMap(\.analyticsKind) where !kinds.contains(kind) { kinds.append(kind) }
        return kinds
    }
}

/// The sidebar's sections, for `sidebar_areas_used`.
nonisolated enum FlixSidebarArea: Hashable, Sendable {
    case activity, threads, kinds, smartFilters, favorites
}

extension FlixFilter {
    /// The section a row of this filter's list reports.
    nonisolated var analyticsSection: AnalyticsFlixSection {
        switch self {
        case .activity(.all): .stream
        case .activity(.flagged): .flagged
        case .activity: .activityFilter
        case .kind: .kindFilter
        case .thread: .thread
        case .smart: .smartFilter
        case .favorite: .favorites
        }
    }

    nonisolated var sidebarArea: FlixSidebarArea {
        switch self {
        case .activity: .activity
        case .kind: .kinds
        case .thread: .threads
        case .smart: .smartFilters
        case .favorite: .favorites
        }
    }
}

extension FlixSmartFilterRule {
    /// A Smart Filter rule's kind. A minimum total is read from the file's content, so it counts as
    /// a `meaning` rule; a time limit counts as `event`, like the activity it narrows.
    nonisolated var analyticsRuleKind: AnalyticsFlixRuleKind {
        switch self {
        case .nameContains: .name
        case .locationContains, .sourceContains: .location
        case .kind, .fileExtension: .kind
        case .activity, .withinDays: .event
        case .flagged: .tag
        case .about, .amountOver: .meaning
        }
    }

    /// A search token's type.
    nonisolated var analyticsTokenType: AnalyticsFlixQueryTokenType {
        switch self {
        case .activity, .flagged: .event
        case .kind, .fileExtension: .kind
        case .withinDays: .time
        case .amountOver: .amount
        case .about, .nameContains: .about
        case .locationContains, .sourceContains: .place
        }
    }
}

extension AnalyticsFlixPageKind {
    /// Webmail hosts, matched exactly or as a parent domain. The host itself is never reported.
    nonisolated static let webmailHosts: Set<String> = [
        "mail.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com", "mail.yahoo.com",
        "app.fastmail.com", "mail.proton.me", "mail.zoho.com", "mail.aol.com", "navigator-bs.gmx.com",
        "web.de", "gmx.net", "mail.yandex.com", "app.hey.com",
    ]

    /// The kind of a link's page, from its address: a web document (`FlixWebDocuments`), webmail,
    /// or any other page. Upload forms are only known from a window's reading.
    nonisolated init(url: URL) {
        if FlixWebDocuments.isWebDocument(url) { self = .webDocument; return }
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
        let isWebmail = Self.webmailHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            || (host.hasSuffix("icloud.com") && url.path.hasPrefix("/mail"))
        self = isWebmail ? .webmail : .otherPage
    }

    /// The kind of the page in a browser window, from what "Fits this window" read in it.
    nonisolated init(_ kind: FlixWindowDemand.PageKind, url: URL? = nil) {
        switch kind {
        case .upload: self = .uploadForm
        case .document: self = .webDocument
        case .mail: self = .webmail
        case .chat, .other: self = url.map(AnalyticsFlixPageKind.init(url:)) ?? .otherPage
        }
    }
}

extension AnalyticsFlixFolder {
    /// The well-known place a watched folder is, or `other`.
    nonisolated init(path: String, home: String = NSHomeDirectory()) {
        let path = FlixPaths.standardized(path)
        let places: [(String, AnalyticsFlixFolder)] = [
            ("/Desktop", .desktop), ("/Documents", .documents), ("/Downloads", .downloads),
            ("/Library/Mobile Documents/com~apple~CloudDocs", .icloudDrive),
        ]
        self = places.first { FlixPaths.standardized(home + $0.0) == path }?.1 ?? .other
    }
}

extension AnalyticsShortcutCombo {
    /// The token for a Flix shortcut, from its key code by position (not by the layout's character).
    nonisolated init(_ combo: FlixShortcutCombo) {
        let modifiers = combo.modifiers
        self.init(keyName: Self.keyName(for: combo.keyCode), control: modifiers.contains(.control),
                  option: modifiers.contains(.option), shift: modifiers.contains(.shift),
                  command: modifiers.contains(.command))
    }

    /// The fixed name of a virtual key code, or `other`.
    nonisolated static func keyName(for keyCode: UInt16) -> String {
        keyCodeNames[Int(keyCode)] ?? "other"
    }

    private nonisolated static let keyCodeNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
            kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
            kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
            kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
            kVK_ANSI_Y: "y", kVK_ANSI_Z: "z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "space", kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up",
            kVK_DownArrow: "down", kVK_Return: "return", kVK_ANSI_KeypadEnter: "enter", kVK_Tab: "tab",
            kVK_Delete: "delete", kVK_ForwardDelete: "fwddelete", kVK_Escape: "escape", kVK_Home: "home",
            kVK_End: "end", kVK_PageUp: "pageup", kVK_PageDown: "pagedown", kVK_ANSI_Minus: "minus",
            kVK_ANSI_Equal: "equal", kVK_ANSI_LeftBracket: "lbracket", kVK_ANSI_RightBracket: "rbracket",
            kVK_ANSI_Semicolon: "semicolon", kVK_ANSI_Quote: "quote", kVK_ANSI_Comma: "comma",
            kVK_ANSI_Period: "period", kVK_ANSI_Slash: "slash", kVK_ANSI_Backslash: "backslash",
            kVK_ANSI_Grave: "grave",
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() { names[code] = "f\(index + 1)" }
        return names
    }()
}

extension FlixSettings {
    /// The settings as `setting_changed` (area `flix`) compares them: the reflected model with the
    /// watched folders and excluded sites as counts (`watched_folder_count`, `excluded_site_count`)
    /// and the shortcut as `shortcut_customized` and `shortcut_combo`. Folder paths, typed hosts, and
    /// the key's printed character never appear.
    nonisolated var analyticsProperties: AnalyticsProperties {
        var properties = AnalyticsProperties(reflecting: self)
        properties.renameKey("watched_folders_count", to: "watched_folder_count")
        properties.renameKey("excluded_sites_count", to: "excluded_site_count")
        properties.renameKey("flix_pick_excluded_apps_count", to: "flix_pick_excluded_app_count")
        properties["shortcut_customized"] = AnalyticsValue(shortcut != .default)
        properties["shortcut_combo"] = AnalyticsValue(AnalyticsShortcutCombo(shortcut))
        return properties
    }
}

extension FlixCoordinator {
    /// Flix Files' person properties: switches and counts only.
    var analyticsProfile: AnalyticsContextInputs.Flix {
        let items = history.items
        return AnalyticsContextInputs.Flix(
            enabled: settings.isEnabled, tileShown: showsTile, menuBar: settings.isEnabled && settings.showsMenuBarItem,
            favoritesCount: history.favorites.count, flagsCount: items.count(where: \.isFlagged),
            smartFilterCount: history.smartFilters.count, historyCount: items.count,
            linkTracking: settings.isEnabled && settings.tracksLinks, linkCount: items.count { $0.link != nil },
            shortcutCustomized: settings.shortcut != .default)
    }
}

extension AnalyticsFlixDrop {
    /// A drop report for `items`.
    ///
    /// - Parameters:
    ///   - place: The first item's section and rank in the panel; nil for the tile.
    ///   - plan: The drag's plan, whose substitutions are the converted copies it carried.
    @MainActor
    init(items: [FlixItem], source: AnalyticsFlixDropSource, place: (section: AnalyticsFlixSection, rank: Int?)?,
         target: AnalyticsFlixDropTarget?, targetCategory: FlixAppCategory?, pageKind: AnalyticsFlixPageKind?,
         plan: FlixDragPlan?, warning: AnalyticsFlixWarning, resolution: AnalyticsFlixWarningResolution?,
         pinned: Bool, predicted: Bool) {
        let converted = items.first { plan?.substitutions[$0.id] != nil }
        self.init(source: source, section: place?.section, rank: place?.rank, itemCount: items.count,
                  itemKinds: items.analyticsKinds, containsFolder: items.contains { $0.kind == .folder },
                  containsLink: items.contains { $0.kind == .link }, target: target, targetCategory: targetCategory,
                  pageKind: pageKind, converted: converted != nil,
                  convertedFrom: converted.flatMap { item in item.contentType.flatMap(AnalyticsFileType.init) },
                  convertedTo: converted.flatMap { plan?.substitutions[$0.id] }.flatMap(AnalyticsFileType.init(url:)),
                  convertMs: converted == nil ? nil : plan?.convertMs, warning: warning, warningResolution: resolution,
                  panelPinned: pinned, predicted: predicted)
    }
}
