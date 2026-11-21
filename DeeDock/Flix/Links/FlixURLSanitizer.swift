import Foundation

/// Cleans a page address before Flix Files stores it: no sign-in tokens, signatures, or session
/// identifiers, and one stable form per page so the history keeps one row for it.
///
/// What is removed:
/// - user name and password, and the fragment (it can carry OAuth tokens such as
///   `#access_token=…`, and it makes one page look like many);
/// - query keys that carry credentials or sessions (``secretKeys``, compared case-insensitively),
///   any key starting with `x-amz-` or `x-goog-` (signed cloud storage links), and the whole set
///   of signing parameters once a signature is present (Azure SAS, CloudFront);
/// - click trackers (`utm_*`, `fbclid`, `gclid`, …), which only split one page into several rows.
///
/// The scheme and host are lowercased, a default port is dropped, and an empty query disappears.
/// Only `http` and `https` addresses are accepted.
nonisolated enum FlixURLSanitizer {
    /// Query keys that carry a credential, a session, or a one-time code.
    static let secretKeys: Set<String> = [
        "token", "access_token", "refresh_token", "id_token", "auth", "auth_token", "authorization",
        "session", "sessionid", "session_id", "sid", "jsessionid", "phpsessid", "sig", "signature",
        "key", "apikey", "api_key", "code", "state", "nonce", "ticket", "otp", "password", "pass", "pwd",
        "secret", "client_secret", "expires", "key-pair-id", "policy", "googleaccessid", "credential",
        "samlresponse", "samlrequest", "magic_link", "login_token", "reset_token", "invite_token",
    ]

    /// Key prefixes of signed cloud storage links.
    static let secretPrefixes = ["x-amz-", "x-goog-", "x-ms-"]

    /// Azure shared access signature parameters, removed together once `sig` is present.
    static let signingKeys: Set<String> = ["sv", "ss", "srt", "sp", "se", "st", "spr", "sr", "si", "skoid", "sktid"]

    /// Click trackers that only make one page look like several.
    static let trackerKeys: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "_hsenc", "_hsmi"]

    /// The cleaned address, or nil when it is not a web page.
    static func sanitize(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.fragment = nil
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if let items = components.queryItems {
            let names = Set(items.map { $0.name.lowercased() })
            let signed = names.contains("sig") || names.contains("signature") || names.contains("x-amz-signature")
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if secretKeys.contains(name) || trackerKeys.contains(name) || name.hasPrefix("utm_") { return false }
                if secretPrefixes.contains(where: name.hasPrefix) { return false }
                if signed, signingKeys.contains(name) { return false }
                return true
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    /// How many credentials ``sanitize(_:)`` drops from `url`: a user name or password, a fragment
    /// that carries a token, and each secret or signing query key. Click trackers are not counted.
    static func removedSecretCount(_ url: URL) -> Int {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return 0 }
        var count = (components.user != nil || components.password != nil) ? 1 : 0
        if let fragment = components.fragment?.lowercased(),
           secretKeys.contains(where: { fragment.contains($0 + "=") }) { count += 1 }
        guard let items = components.queryItems else { return count }
        let names = Set(items.map { $0.name.lowercased() })
        let signed = names.contains("sig") || names.contains("signature") || names.contains("x-amz-signature")
        count += items.count { item in
            let name = item.name.lowercased()
            return secretKeys.contains(name) || secretPrefixes.contains(where: name.hasPrefix)
                || (signed && signingKeys.contains(name))
        }
        return count
    }

    static func sanitize(_ string: String) -> URL? {
        URL(string: string).flatMap(sanitize)
    }
}
