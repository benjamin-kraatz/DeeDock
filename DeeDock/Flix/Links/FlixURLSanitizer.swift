import Foundation

/// Decides what of a page address Flix Files may store, and cleans it: one stable form per page,
/// and nothing that could sign someone in.
///
/// The policy is conservative because a stored address outlives the moment it was seen:
/// - **Always removed**: the user name and password, the fragment (it can carry OAuth tokens such
///   as `#access_token=…`), and the whole query. A query is kept only for the few web-document
///   addresses that need it to name the document (``documentQueryKeys``: OneDrive's `resid`,
///   SharePoint's `sourcedoc`, Confluence's `pageId`), and then only those keys.
/// - **Never stored at all** (``Cleaned/skipped``): addresses whose path is a credential-bearing
///   route — password resets, email verification, invitations, magic links, sign-in, OAuth
///   callbacks, tokens, unsubscribe and activation links, share links (``credentialWords``) — and
///   addresses with a high-entropy path segment that looks like a secret (``looksLikeSecret(_:)``).
/// - **Exception**: a web document ``FlixWebDocuments`` recognizes (Google Docs, Sheets, and
///   Slides, Figma, Notion, Linear, Office 365, Atlassian) keeps its path, because the document ID
///   lives there and is not a credential, and its title slug may say "reset" or "invite" without
///   being a route. Such an address is still left out when one whole path segment is a route word
///   (``documentRouteWords``: `/invite/…`, `/share/…`, `/login`).
///
/// The scheme and host are lowercased, a default port is dropped. Only `http` and `https`
/// addresses are accepted. Every caller counts ``Cleaned/removedSecrets`` (and a skip as one) into
/// `flix_link_tokens_stripped`.
nonisolated enum FlixURLSanitizer {
    /// What may be stored of an address.
    enum Cleaned: Equatable, Sendable {
        /// The address to store, and how many secrets cleaning removed from it.
        case kept(URL, removedSecrets: Int)
        /// A web address that must not be stored at all: it carries a credential in its path.
        case skipped
        /// Not a web page (`file:`, `mailto:`, …).
        case notWeb

        /// The address to store, if any.
        var url: URL? { if case .kept(let url, _) = self { url } else { nil } }

        /// What `flix_link_tokens_stripped` counts: the secrets removed, or one for a skipped address.
        var removedSecrets: Int {
            switch self {
            case .kept(_, let removed): removed
            case .skipped: 1
            case .notWeb: 0
            }
        }
    }

    /// Query keys that carry a credential, a session, or a one-time code. They are removed with the
    /// rest of the query; this list only decides what counts as a removed secret.
    static let secretKeys: Set<String> = [
        "token", "access_token", "refresh_token", "id_token", "auth", "auth_token", "authorization", "authkey",
        "session", "sessionid", "session_id", "sid", "jsessionid", "phpsessid", "sig", "signature",
        "key", "apikey", "api_key", "code", "state", "nonce", "ticket", "otp", "password", "pass", "pwd",
        "secret", "client_secret", "expires", "key-pair-id", "policy", "googleaccessid", "credential",
        "samlresponse", "samlrequest", "magic_link", "login_token", "reset_token", "invite_token", "rlkey",
    ]

    /// Key prefixes of signed cloud storage links, counted as secrets.
    static let secretPrefixes = ["x-amz-", "x-goog-", "x-ms-"]

    /// Query keys kept for web documents whose address names the document in its query, by host
    /// (the host itself or a subdomain of it). No other query survives.
    static let documentQueryKeys: [String: Set<String>] = [
        "onedrive.live.com": ["resid", "cid"],
        "sharepoint.com": ["sourcedoc"],
        "atlassian.net": ["pageid"],
    ]

    /// Path words of credential-bearing routes. A path segment split into words on anything that is
    /// not a letter or digit, or the segment with its separators removed, matching one of these
    /// makes the address unstorable.
    static let credentialWords: Set<String> = [
        "reset", "resetpassword", "passwordreset", "forgotpassword", "recover", "recovery",
        "verify", "verification", "verifyemail", "confirm", "confirmation", "confirmemail",
        "invite", "invites", "invitation", "invitations", "magic", "magiclink",
        "login", "logon", "signin", "sso", "saml", "oauth", "oauth2", "openid", "authorize", "authenticate",
        "authentication", "auth", "callback", "callbacks", "token", "tokens", "otp", "2fa", "mfa",
        "unsubscribe", "optout", "activate", "activation", "onetime", "passwordless",
        "share", "shared", "sharing", "sharelink",
    ]

    /// First path segments of share links whose key follows (Dropbox's `/s/<key>`, `/scl/fi/<key>`).
    static let shareLinkPrefixes: Set<String> = ["s", "scl"]

    /// Whole path segments that make even a web-document address unstorable.
    static let documentRouteWords: Set<String> = [
        "invite", "invites", "invitation", "share", "shared", "sharing", "login", "signin", "auth", "oauth",
        "oauth2", "sso", "saml", "callback", "token", "verify", "confirm", "reset", "magic", "unsubscribe",
    ]

    /// The cleaned address, or nil when it is not a web page or must not be stored.
    static func sanitize(_ url: URL) -> URL? { clean(url).url }

    static func sanitize(_ string: String) -> URL? {
        URL(string: string).flatMap(sanitize)
    }

    /// Applies the policy above to `url`.
    static func clean(_ url: URL) -> Cleaned {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return .notWeb }
        var removed = (components.user != nil || components.password != nil) ? 1 : 0
        if let fragment = components.fragment?.lowercased(), fragment.contains("=") { removed += 1 }
        let items = components.queryItems ?? []
        let allowed = documentKeys(for: host)
        removed += items.count { item in
            let name = item.name.lowercased()
            return !allowed.contains(name) && (secretKeys.contains(name) || secretPrefixes.contains(where: name.hasPrefix))
        }

        // The web-document check reads the address as the browser showed it, query included
        // (OneDrive names its documents there).
        let isDocument = FlixWebDocuments.isWebDocument(url)
        let segments = components.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        if isDocument {
            if segments.contains(where: { documentRouteWords.contains($0.lowercased()) }) { return .skipped }
        } else if segments.contains(where: isCredentialRoute) || segments.contains(where: looksLikeSecret)
                    || segments.first.map({ shareLinkPrefixes.contains($0.lowercased()) }) == true {
            return .skipped
        }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.fragment = nil
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        let kept = isDocument ? items.filter { allowed.contains($0.name.lowercased()) } : []
        components.queryItems = kept.isEmpty ? nil : kept
        if components.path.isEmpty { components.path = "/" }
        guard let cleaned = components.url else { return .notWeb }
        return .kept(cleaned, removedSecrets: removed)
    }

    /// How many secrets cleaning removes from `url`, a skipped address counting as one, for
    /// `flix_link_tokens_stripped`.
    static func removedSecretCount(_ url: URL) -> Int { clean(url).removedSecrets }

    /// Whether a path segment names a credential-bearing route (``credentialWords``).
    static func isCredentialRoute(_ segment: String) -> Bool {
        let lower = segment.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: credentialWords.contains) { return true }
        return credentialWords.contains(String(lower.filter { $0.isLetter || $0.isNumber }))
    }

    /// Whether a path segment looks like a secret rather than a name: a UUID, or at least 24
    /// characters mixing letters and digits whose pieces (split on `-`, `_`, `.`, `~`) average 12
    /// characters or more. Slugs ("how-to-fix-error-404-in-2024") are made of short words and pass.
    static func looksLikeSecret(_ segment: String) -> Bool {
        if UUID(uuidString: segment) != nil { return true }
        guard segment.count >= 24, segment.contains(where: \.isLetter), segment.contains(where: \.isNumber) else { return false }
        let pieces = segment.split(whereSeparator: { "-_.~".contains($0) })
        guard !pieces.isEmpty else { return false }
        let average = Double(pieces.reduce(0) { $0 + $1.count }) / Double(pieces.count)
        return average >= 12
    }

    private static func documentKeys(for host: String) -> Set<String> {
        documentQueryKeys.first { FlixSiteExclusions.host(host, isWithin: $0.key) }?.value ?? []
    }
}
