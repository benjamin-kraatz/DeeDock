import AppKit

/// What kind of app a window belongs to, derived from what the app can open and its App Store
/// category, never from its name.
///
/// The sensitive guard asks only before files leave for an outside target (``isOutside``); window
/// reading uses the category to tell a mail draft from a chat. Phase C's analytics reports the same
/// categories instead of app names.
nonisolated enum FlixAppCategory: String, Sendable, CaseIterable {
    case browser, mail, chat, office, design, developer, finder, other, none

    /// A destination that sends files off this Mac: a browser upload, an email, a message.
    var isOutside: Bool { self == .browser || self == .mail || self == .chat }

    /// Chat apps whose bundles declare no social-networking category.
    static let chatBundles: Set<String> = [
        "com.apple.MobileSMS", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams2",
        "com.microsoft.teams", "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram",
        "org.telegram.desktop", "org.whispersystems.signal-desktop", "us.zoom.xos", "com.facebook.archon",
        "com.apple.FaceTime", "im.riot.app", "com.electron.element",
    ]

    /// The category for a running app. Main actor: it asks Launch Services which apps open web and
    /// mail addresses, cached after the first call.
    @MainActor
    static func of(bundleIdentifier: String?, bundleURL: URL?) -> FlixAppCategory {
        guard let bundleIdentifier else { return .none }
        if bundleIdentifier == "com.apple.finder" { return .finder }
        if let bundleURL {
            if handlers.web.contains(bundleURL.standardizedFileURL) { return .browser }
            if handlers.mail.contains(bundleURL.standardizedFileURL) { return .mail }
        }
        if chatBundles.contains(bundleIdentifier) { return .chat }
        let category = bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        return category.map(Self.from(appStoreCategory:)) ?? .other
    }

    @MainActor
    static func of(_ context: FlixFrontmostContext?) -> FlixAppCategory {
        guard let context else { return .none }
        let url = NSRunningApplication(processIdentifier: context.processIdentifier)?.bundleURL
        return of(bundleIdentifier: context.bundleIdentifier, bundleURL: url)
    }

    static func from(appStoreCategory: String) -> FlixAppCategory {
        switch appStoreCategory {
        case "public.app-category.social-networking": .chat
        case "public.app-category.productivity", "public.app-category.business", "public.app-category.finance",
             "public.app-category.education": .office
        case "public.app-category.graphics-design", "public.app-category.photography", "public.app-category.video":
            .design
        case "public.app-category.developer-tools": .developer
        default: .other
        }
    }

    /// Apps that open `https:` and `mailto:` addresses, read once from Launch Services.
    @MainActor private static var cachedHandlers: (web: Set<URL>, mail: Set<URL>)?

    @MainActor private static var handlers: (web: Set<URL>, mail: Set<URL>) {
        if let cachedHandlers { return cachedHandlers }
        let workspace = NSWorkspace.shared
        let web = URL(string: "https://example.com").map { Set(workspace.urlsForApplications(toOpen: $0).map(\.standardizedFileURL)) } ?? []
        let mail = URL(string: "mailto:someone@example.com").map { Set(workspace.urlsForApplications(toOpen: $0).map(\.standardizedFileURL)) } ?? []
        // Apps that open both (some browsers register mailto) count as browsers.
        let handlers = (web: web, mail: mail.subtracting(web))
        cachedHandlers = handlers
        return handlers
    }

    /// Forgets the handler lists, for when apps were installed or removed.
    @MainActor static func invalidate() { cachedHandlers = nil }
}
