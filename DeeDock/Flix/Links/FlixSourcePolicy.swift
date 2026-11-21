import Foundation

/// What Flix Files may keep of the page a download came from.
///
/// A download's page (`kMDItemWhereFroms`) is web history, so it follows the web-link settings
/// even though it arrives with a file. macOS does not record whether a download came from a
/// private window, so a full page address is stored only with positive evidence that it did not:
/// - **Web links on, site not excluded, window verified**: the cleaned page (``FlixURLSanitizer``)
///   and its host. Verified means the link tracker saw the download arrive while a normal (not
///   private) window of a browser whose private windows can be told apart showed that very page
///   (`FlixLinkTracker.recorded(_:)`); it then attaches the page with
///   `FlixHistoryDocument.attachVerifiedSource(_:toPath:)`, which sets
///   ``FlixItem/sourcePageIsVerified``.
/// - **Anything less** (web links off, Flix Files off, no verification): only the bare host, for
///   the row's "Downloaded from example.com" line.
/// - **Excluded site** (the person's list, or banking and health while that is on): nothing, not
///   even the host.
///
/// Applied to every source event before it reaches the history or the link tracker
/// (`FlixCoordinator.receive`), and to the stored history at launch and whenever these settings
/// change, so items saved under an earlier, looser policy are stripped too: a stored page without
/// the verified marker keeps only its host. Stripping is one-way: turning web links on later does
/// not bring an address back.
nonisolated enum FlixSourcePolicy {
    /// `page` and `host` as the settings allow them. A page survives only while web links are on and
    /// the site is not excluded; the caller decides whether it is verified enough to store.
    static func allowed(page: URL?, host: String?, settings: FlixSettings) -> (page: URL?, host: String?) {
        let exclusions = FlixSiteExclusions(settings: settings)
        let derived = page.flatMap(FlixPaths.displayHost) ?? host
        guard let derived else { return (nil, nil) }
        if exclusions.excludes(host: derived) { return (nil, nil) }
        guard settings.isEnabled, settings.tracksLinks, let page else { return (nil, derived) }
        // A page stored before the stricter cleaning is cleaned again; one that must not be stored
        // keeps only its host.
        return (FlixURLSanitizer.sanitize(page), derived)
    }

    /// The event as the settings allow it, page included. The history takes only the host from an
    /// event; the page is the link tracker's candidate for verification.
    static func apply(to event: FlixActivityEvent, settings: FlixSettings) -> FlixActivityEvent {
        guard event.sourcePage != nil || event.sourceHost != nil else { return event }
        var event = event
        (event.sourcePage, event.sourceHost) = allowed(page: event.sourcePage, host: event.sourceHost, settings: settings)
        if event.sourcePage == nil { event.sourcePageIdentity = nil }
        return event
    }

    /// The item as the settings allow it to be stored: a page without the verified marker keeps
    /// only its host.
    static func apply(to item: FlixItem, settings: FlixSettings) -> FlixItem {
        guard item.sourcePage != nil || item.sourceHost != nil || item.sourcePageIsVerified != nil else { return item }
        var item = item
        (item.sourcePage, item.sourceHost) = allowed(page: item.sourcePage, host: item.sourceHost, settings: settings)
        if item.sourcePageIsVerified != true { item.sourcePage = nil }
        if item.sourcePage == nil { item.sourcePageIsVerified = nil }
        return item
    }
}
