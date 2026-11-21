import Foundation

/// What Flix Files may keep of the page a download came from.
///
/// A download's page (`kMDItemWhereFroms`) is web history, so it follows the web-link settings
/// even though it arrives with a file:
/// - **Web links on, site not excluded**: the cleaned page (``FlixURLSanitizer``) and its host.
/// - **Web links off** (or Flix Files off): only the bare host, for the row's "Downloaded from
///   example.com" line. The page address is never stored.
/// - **Excluded site** (the person's list, or banking and health while that is on): nothing, not
///   even the host.
///
/// Applied to every source event before it reaches the history (`FlixCoordinator.receive`), and
/// to the stored history at launch and whenever these settings change, so items saved under an
/// earlier, looser policy are stripped too. Stripping is one-way: turning web links on later does
/// not bring an address back.
nonisolated enum FlixSourcePolicy {
    /// `page` and `host` as the settings allow them to be stored.
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

    /// The event as the settings allow it to be stored.
    static func apply(to event: FlixActivityEvent, settings: FlixSettings) -> FlixActivityEvent {
        guard event.sourcePage != nil || event.sourceHost != nil else { return event }
        var event = event
        (event.sourcePage, event.sourceHost) = allowed(page: event.sourcePage, host: event.sourceHost, settings: settings)
        return event
    }

    /// The item as the settings allow it to be stored.
    static func apply(to item: FlixItem, settings: FlixSettings) -> FlixItem {
        guard item.sourcePage != nil || item.sourceHost != nil else { return item }
        var item = item
        (item.sourcePage, item.sourceHost) = allowed(page: item.sourcePage, host: item.sourceHost, settings: settings)
        return item
    }
}
