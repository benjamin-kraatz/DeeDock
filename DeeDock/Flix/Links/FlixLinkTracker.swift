import AppKit
import CoreGraphics

/// Web links (off by default): keeps the pages that matter to your files as Flix items.
///
/// Triggers, all while **Track web links** is on:
/// - **Downloads**: the page a download came from (`kMDItemWhereFroms`, cleaned and already
///   allowed by ``FlixSourcePolicy``), recorded when the file arrives — but only when the download's
///   privacy can be verified: it arrived within ``downloadWindow`` while a browser with a
///   private-window check was in front, that window reads as normal, and its page is on the
///   download's site. macOS does not record whether a download came from a private window, so
///   anything less keeps just the host on the file's row. Its row then reads "Source of “Invoice.pdf”".
/// - **Drops**: after a Flix file is dropped outside while a browser was the window in front, that
///   browser's page; its row reads "↑ You sent 2 files here".
/// - **Web documents** (``FlixWebDocuments``) that stay in front for 30 seconds.
/// - **Pages you read** (its own switch): any page in front for two minutes with keyboard or
///   pointer input in the last minute (`CGEventSource.secondsSinceLastEventType`, no monitor).
/// - **Save this page** and URLs dropped on the panel: deliberate saves, kept from any browser and
///   any site.
///
/// Rules for everything automatic: the browser must be one whose private windows can be told apart
/// (``FlixBrowserFamily/tracksAutomatically``) and the window must read as normal, never unknown;
/// excluded sites (``FlixSiteExclusions``) are skipped. Addresses are cleaned by
/// ``FlixURLSanitizer``. Only the address, title, browser, and time are stored, one item per
/// address. Each new link item reports `flix_link_saved` with its trigger and page kind (never the
/// address); skipped private and excluded pages and removed credentials are counted for
/// `usage_summary`. Pages are read through Accessibility only when a browser's window title changes
/// (``FlixFrontWindowObserver``) or a trigger fires; nothing polls. Dwell timers are single sleeping
/// tasks owned here, cancelled by the next change and by ``stop()``. Main actor.
@MainActor
final class FlixLinkTracker {
    static let pagesYouReadDwell: Duration = .seconds(120)
    /// "Recent input" for pages you read: a key press or pointer move within this many seconds.
    static let recentInput: TimeInterval = 60
    /// How recent a download must be for the browser in front to vouch for it.
    static let downloadWindow: TimeInterval = 120

    private let history: FlixHistory
    private let relationsFile: FlixJSONFile<FlixLinkRelationsDocument>?
    private var relations = FlixLinkRelationsDocument()
    private var loaded = false
    private var settings = FlixSettings()
    private var readTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    /// Download sources by cleaned page address, rebuilt when the history changes.
    private var sourceNames: [String: [String]] = [:]
    private var itemIDs = Set<FlixItem.ID>()

    /// - Parameter folder: Where `links.json` lives; nil keeps relations in memory.
    init(history: FlixHistory, folder: URL?) {
        self.history = history
        relationsFile = folder.map { FlixJSONFile(url: $0.appending(path: "links.json")) }
    }

    var isTracking: Bool { settings.isEnabled && settings.tracksLinks }

    func apply(_ settings: FlixSettings) {
        self.settings = settings
        if !isTracking { cancelTimers() }
    }

    func stop() {
        cancelTimers()
        relationsFile?.flush()
    }

    // MARK: Triggers

    /// The window in front changed. Starts the dwell timers when a browser shows a page.
    func frontWindowChanged(_ app: NSRunningApplication) {
        cancelTimers()
        guard isTracking, let family = FlixBrowserCatalog.family(of: app), family.tracksAutomatically else { return }
        let pid = app.processIdentifier
        let bundle = app.bundleIdentifier
        readTask = Task { [weak self] in
            guard let page = await FlixBrowserPageReader.read(processIdentifier: pid, family: family, bundleIdentifier: bundle),
                  let self, !Task.isCancelled, trackable(page) else { return }
            startDwell(on: page, pid: pid, family: family)
        }
    }

    /// Files arrived. A download's page becomes a link item only when the browser in front vouches
    /// for it (see the type's documentation); the check reads that browser's window once, off the
    /// main actor.
    func recorded(_ events: [FlixActivityEvent]) {
        guard isTracking else { return }
        let now = Date.now
        let downloads = events.filter { event in
            event.activity == .downloaded && event.sourcePage != nil && now.timeIntervalSince(event.date) <= Self.downloadWindow
        }
        guard !downloads.isEmpty, let app = NSWorkspace.shared.frontmostApplication,
              let family = FlixBrowserCatalog.family(of: app), family.tracksAutomatically else { return }
        let pid = app.processIdentifier
        let bundle = app.bundleIdentifier
        Task { [weak self] in
            let front = await FlixBrowserPageReader.read(processIdentifier: pid, family: family, bundleIdentifier: bundle)
            guard let self, isTracking else { return }
            guard let front, front.privacy == .normal else {
                Analytics.count(.linksPrivateSkipped)
                return
            }
            let exclusions = FlixSiteExclusions(settings: settings)
            for event in downloads {
                guard let source = event.sourcePage, Self.sameSite(source, front.url) else { continue }
                guard !exclusions.excludes(source) else {
                    Analytics.count(.linksExcludedSkipped)
                    continue
                }
                record(source, title: nil, browser: front.browserBundleIdentifier, date: event.date,
                       trigger: .downloadSource, removedSecrets: 0)
            }
        }
    }

    /// Whether two pages are on the same site: one host is the other or a subdomain of it.
    static func sameSite(_ a: URL, _ b: URL) -> Bool {
        guard let first = FlixPaths.displayHost(of: a), let second = FlixPaths.displayHost(of: b) else { return false }
        return FlixSiteExclusions.host(first, isWithin: second) || FlixSiteExclusions.host(second, isWithin: first)
    }

    /// Flix items were dropped outside while `context`'s app was in front. A normal browser window's
    /// page is recorded with the items it received.
    func dropped(_ items: [FlixItem], context: FlixFrontmostContext?) {
        guard isTracking, let context, let family = FlixBrowserCatalog.family(processIdentifier: context.processIdentifier),
              family.tracksAutomatically else { return }
        let ids = items.filter { $0.link == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            guard let page = await FlixBrowserPageReader.read(processIdentifier: context.processIdentifier, family: family,
                                                              bundleIdentifier: context.bundleIdentifier),
                  let self, trackable(page) else { return }
            loadIfNeeded()
            relations.record(sent: ids, to: page.url)
            relationsFile?.schedule(relations)
            record(page.url, title: page.title, browser: page.browserBundleIdentifier, date: .now, trigger: .sentTo,
                   removedSecrets: page.removedSecrets)
        }
    }

    /// The page in front for **Save this page**: any browser, private or not, since saving is the
    /// person's own choice. Nil when the app is no browser or shows no page.
    func currentPage(for context: FlixFrontmostContext?) async -> FlixBrowserPage? {
        guard isTracking, let context, let family = FlixBrowserCatalog.family(processIdentifier: context.processIdentifier)
        else { return nil }
        return await FlixBrowserPageReader.read(processIdentifier: context.processIdentifier, family: family,
                                                bundleIdentifier: context.bundleIdentifier)
    }

    /// The page in a browser window for the Fits card's label, read without any tracking.
    func page(for context: FlixFrontmostContext) async -> FlixBrowserPage? {
        guard let family = FlixBrowserCatalog.family(processIdentifier: context.processIdentifier) else { return nil }
        return await FlixBrowserPageReader.read(processIdentifier: context.processIdentifier, family: family,
                                                bundleIdentifier: context.bundleIdentifier)
    }

    /// **Save this page**.
    func save(_ page: FlixBrowserPage) {
        record(page.url, title: page.title, browser: page.browserBundleIdentifier, date: .now, trigger: .savedButton,
               removedSecrets: page.removedSecrets)
    }

    // MARK: Relation lines

    /// Rebuilds the "Source of …" index. O(items), called on history changes.
    func historyChanged(_ items: [FlixItem]) {
        var names: [String: [String]] = [:]
        for item in items where item.link == nil {
            // Stored pages are already cleaned and allowed (`FlixSourcePolicy`).
            guard let source = item.sourcePage else { continue }
            names[source.absoluteString, default: []].append(item.name)
        }
        sourceNames = names
        itemIDs = Set(items.map(\.id))
    }

    /// The link row's relation line, or nil.
    func relationLine(for item: FlixItem) -> String? {
        guard let link = item.link else { return nil }
        loadIfNeeded()
        let key = link.url.absoluteString
        let sent = (relations.sent[key] ?? []).filter(itemIDs.contains).count
        return FlixLinkRelationLine.line(sources: sourceNames[key] ?? [], sentCount: sent)
    }

    // MARK: Pieces

    private func canTrack(_ page: FlixBrowserPage) -> Bool {
        isTracking && page.privacy == .normal && !FlixSiteExclusions(settings: settings).excludes(page.url)
    }

    /// ``canTrack(_:)`` for a page a trigger just read, counting why one is skipped.
    private func trackable(_ page: FlixBrowserPage) -> Bool {
        guard isTracking else { return false }
        if page.privacy != .normal {
            Analytics.count(.linksPrivateSkipped)
            return false
        }
        if FlixSiteExclusions(settings: settings).excludes(page.url) {
            Analytics.count(.linksExcludedSkipped)
            return false
        }
        return true
    }

    private func startDwell(on page: FlixBrowserPage, pid: pid_t, family: FlixBrowserFamily) {
        let isDocument = FlixWebDocuments.isWebDocument(page.url)
        let readsPages = settings.tracksPagesYouRead
        guard isDocument || readsPages else { return }
        dwellTask = Task { [weak self] in
            var kept = false
            if isDocument {
                try? await Task.sleep(for: FlixWebDocuments.dwell)
                guard let self, !Task.isCancelled, await stillShowing(page, pid: pid, family: family) else { return }
                record(page.url, title: page.title, browser: page.browserBundleIdentifier, date: .now, trigger: .webDocument,
                       removedSecrets: page.removedSecrets)
                kept = true
            }
            guard readsPages else { return }
            try? await Task.sleep(for: Self.pagesYouReadDwell - (kept ? FlixWebDocuments.dwell : .zero))
            guard let self, !Task.isCancelled, settings.tracksPagesYouRead, Self.hasRecentInput,
                  await stillShowing(page, pid: pid, family: family) else { return }
            record(page.url, title: page.title, browser: page.browserBundleIdentifier, date: .now, trigger: .read,
                   removedSecrets: kept ? 0 : page.removedSecrets)
        }
    }

    /// The same page is still in front of the same browser, in a normal window.
    private func stillShowing(_ page: FlixBrowserPage, pid: pid_t, family: FlixBrowserFamily) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let now = await FlixBrowserPageReader.read(processIdentifier: pid, family: family,
                                                         bundleIdentifier: page.browserBundleIdentifier) else { return false }
        return !Task.isCancelled && now.url == page.url && canTrack(now)
    }

    private static var hasRecentInput: Bool {
        let any = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any) < recentInput
    }

    /// Records a page as a link item. A new item reports `flix_link_saved` once; every recording
    /// counts toward `flix_links_recorded`.
    private func record(_ url: URL, title: String?, browser: String?, date: Date, trigger: AnalyticsFlixLinkTrigger,
                        removedSecrets: Int) {
        let existing = history.items.first { $0.link?.url == url }?.link
        Analytics.count(.linksRecorded)
        Analytics.count(.linkTokensStripped, by: removedSecrets)
        if existing == nil { Analytics.track(.flixLinkSaved(trigger, pageKind: AnalyticsFlixPageKind(url: url))) }
        let link = FlixLink(url: url, title: title ?? existing?.title,
                            browserBundleIdentifier: browser ?? existing?.browserBundleIdentifier)
        history.record(FlixActivityEvent(link: link, name: link.title ?? link.host, kind: .link, activity: .link, date: date))
    }

    private func cancelTimers() {
        readTask?.cancel()
        readTask = nil
        dwellTask?.cancel()
        dwellTask = nil
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        do {
            if let saved = try relationsFile?.load() { relations = saved }
        } catch {
            relationsFile?.quarantine()
        }
    }
}
