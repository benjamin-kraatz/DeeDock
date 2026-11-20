import Foundation

/// A web page Flix Files keeps as an item.
///
/// Phase A stores links only when you drop a URL on the panel. Phase B1 adds link tracking (off by
/// default) and renders link rows with a site monogram; this model is already what it stores.
/// Only the URL, the title, and the browser that showed it are kept: never page contents.
nonisolated struct FlixLink: Codable, Hashable, Sendable {
    /// The page address, with tracking and session parameters already removed by whoever recorded it.
    var url: URL
    /// The page title when known; rows fall back to the host.
    var title: String?
    /// The browser the page was seen in, so reopening uses the same one. Nil opens the default browser.
    var browserBundleIdentifier: String?

    /// The host without a leading `www.`, for the event line and the monogram.
    var host: String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
