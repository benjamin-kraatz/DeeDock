import Foundation

/// Invitation, meeting, short-link, and share-secret addresses that Flix Files never stores.
///
/// Such an address is a credential even when it is short and looks harmless: `discord.gg/abc123`
/// joins a server, `zoom.us/j/123?pwd=…` joins a call, `bit.ly/x` can lead anywhere, and
/// `drive.google.com/…?usp=sharing` opens a file to anyone holding it. ``FlixURLSanitizer`` asks
/// ``isDenied(host:segments:query:)`` before anything else, so even a recognized web document on
/// one of these services is skipped.
///
/// A maintained, best-effort list: it covers the common services and their usual routes, not
/// every invitation format on the web. ``FlixURLSanitizer``'s general rules (credential route words,
/// secret-looking segments, the dropped query and fragment) still apply to everything else. Hosts
/// match themselves and their subdomains.
nonisolated enum FlixShareLinkDenylist {
    /// Hosts whose every address is an invitation, a meeting, a share secret, or a short link that
    /// hides where it goes.
    static let deniedHosts: Set<String> = [
        // Invitations and meetings
        "discord.gg", "chat.whatsapp.com", "wa.me", "signal.group", "signal.me", "meet.google.com", "join.slack.com",
        "calendly.com", "whereby.com", "meet.jit.si", "join.skype.com", "teams.live.com",
        // Short links
        "bit.ly", "t.co", "tinyurl.com", "goo.gl", "ow.ly", "buff.ly", "rebrand.ly", "is.gd", "cutt.ly",
        "lnkd.in", "t.ly", "rb.gy", "tiny.cc", "shorturl.at", "aka.ms", "forms.gle", "g.co",
        // File sharing whose addresses are the share key
        "wetransfer.com", "we.tl", "docsend.com", "1drv.ms", "mega.nz", "mega.io", "send.firefox.com",
        "notion.site",
    ]

    /// Path prefixes, by host, that are invitations or share links on otherwise ordinary sites.
    static let deniedRoutes: [String: [[String]]] = [
        "discord.com": [["invite"]], "discordapp.com": [["invite"]],
        "t.me": [["joinchat"]], "telegram.me": [["joinchat"]],
        "zoom.us": [["j"], ["my"], ["s"], ["w"], ["wc"]],
        "teams.microsoft.com": [["l", "meetup-join"], ["meet"]],
        "slack.com": [["shared_invite"]],
        "icloud.com": [["share"], ["iclouddrive"], ["photos"], ["keynote"], ["pages"], ["numbers"], ["notes"],
                       ["freeform"], ["reminders"], ["invites"]],
        "box.com": [["s"]], "app.box.com": [["s"]],
        "dropbox.com": [["s"], ["scl"], ["sh"], ["t"]],
        "webex.com": [["meet"], ["join"]],
    ]

    /// Route words that mark an invitation or a share on the messaging, meeting, and file-sharing
    /// services in ``messagingHosts``, in any path segment.
    static let messagingRouteWords: Set<String> = ["invite", "join", "j", "s", "share", "my", "meet", "joinchat", "w"]

    /// Messaging, meeting, and file-sharing services where ``messagingRouteWords`` apply.
    static let messagingHosts: Set<String> = [
        "discord.com", "discordapp.com", "t.me", "telegram.me", "telegram.org", "whatsapp.com", "signal.org",
        "zoom.us", "webex.com", "gotomeeting.com", "goto.com", "skype.com", "teams.microsoft.com", "slack.com",
        "dropbox.com", "box.com", "pcloud.com", "mediafire.com", "icloud.com", "wetransfer.com",
    ]

    /// Whether the address must not be stored.
    /// - Parameters:
    ///   - host: Lowercased host.
    ///   - segments: The path's segments, percent-decoded, in order.
    ///   - query: The query items as given, before cleaning drops them.
    static func isDenied(host: String, segments: [String], query: [URLQueryItem]) -> Bool {
        let lower = segments.map { $0.lowercased() }
        if deniedHosts.contains(where: { within(host, $0) }) { return true }
        for (domain, routes) in deniedRoutes where within(host, domain) {
            if routes.contains(where: { lower.starts(with: $0) }) { return true }
        }
        // Telegram's private invitations: t.me/+<key>.
        if within(host, "t.me") || within(host, "telegram.me"), lower.first?.hasPrefix("+") == true { return true }
        if messagingHosts.contains(where: { within(host, $0) }), lower.contains(where: messagingRouteWords.contains) {
            return true
        }
        if within(host, "drive.google.com") { return !isPlainDriveFile(lower, query: query) }
        // SharePoint and OneDrive for work sharing links (`/:w:/g/…`, `/:x:/s/…`) carry the share key;
        // `/:w:/r/…` addresses the document itself.
        if within(host, "sharepoint.com"), let first = lower.first, first.count == 3, first.hasPrefix(":"),
           first.hasSuffix(":"), lower.count > 1, lower[1] != "r" { return true }
        return false
    }

    /// A Google Drive address kept only as the file itself: `/file/d/<id>` (with `/view` or
    /// `/edit` after it), and never with a sharing parameter (`usp=sharing`, `usp=share_link`).
    private static func isPlainDriveFile(_ segments: [String], query: [URLQueryItem]) -> Bool {
        let sharing = query.contains { $0.name.lowercased() == "usp" && ($0.value ?? "").lowercased().hasPrefix("shar") }
        guard !sharing, segments.count >= 3, segments[0] == "file", segments[1] == "d" else { return false }
        return segments.count == 3 || (segments.count == 4 && ["view", "edit", "preview"].contains(segments[3]))
    }

    private static func within(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
