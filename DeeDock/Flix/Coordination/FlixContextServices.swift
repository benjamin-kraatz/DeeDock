import AppKit

/// Phase B1: everything that looks at the window in front or at what leaves Flix Files — Fits this
/// window, the tile's pill, upload conversions, the sensitive file guard, and web links.
///
/// `FlixCoordinator` owns one (``FlixCoordinator/contextServices``, set by `live()`) and calls it
/// from a handful of places: start, stop, settings changes, history changes, recorded events, the
/// panel opening, and drops. It installs its providers into `FlixIntelligence` (`fits` and `drag`;
/// it never touches the other slots) and the panel state's B1 hooks.
///
/// Observers run only while a setting needs them: the front-window observer while the tile's pill
/// or web links are on, the sensitive guard while it is on. ``stop()`` tears all of them down and
/// removes the converted copies. Main actor.
@MainActor
final class FlixContextServices {
    let observer = FlixFrontWindowObserver()
    let fits = FlixFitsProvider()
    let conversions = FlixConversionStore()
    let sensitive: FlixSensitiveGuard
    let interceptor: FlixDragInterceptor
    let links: FlixLinkTracker

    private weak var coordinator: FlixCoordinator?
    private var pageTask: Task<Void, Never>?

    /// - Parameter folder: Where the guard's and the links' JSON files live; nil keeps them in memory.
    init(history: FlixHistory, folder: URL?) {
        sensitive = FlixSensitiveGuard(folder: folder)
        interceptor = FlixDragInterceptor(conversions: conversions, sensitive: sensitive)
        links = FlixLinkTracker(history: history, folder: folder)
    }

    // MARK: Lifecycle

    func start(with coordinator: FlixCoordinator) {
        self.coordinator = coordinator
        // Copies from an earlier run are no longer needed.
        conversions.removeFolder()
        let intelligence = coordinator.intelligence
        fits.annotation = { [weak intelligence] id in intelligence?.annotations[id] }
        fits.browserPage = { [weak self] context in await self?.links.page(for: context) }
        fits.demandReady = { [weak self] context, demand, fitIDs in self?.prepareConversions(context, demand, fitIDs) }
        fits.likelyItem = { [weak intelligence] context, items in intelligence?.likelyItem(for: context, among: items) }
        fits.computed = { [weak coordinator] report in
            Analytics.track(.flixFitsComputed(report))
            coordinator?.metrics.fitsRead(reader: report.reader, readyMs: report.readyMs, shown: report.matches)
        }
        interceptor.demand = { [weak self] context in self?.fits.demand(for: context) }
        interceptor.destinationLabel = { [weak self] context in
            self?.fits.windowLabel(for: context) ?? context?.applicationName
        }
        interceptor.settings = { [weak coordinator] in coordinator?.settings ?? FlixSettings() }
        sensitive.verdictChanged = { [weak coordinator] id, kind in
            coordinator?.intelligence.reviseAnnotation(for: id) { annotation in
                annotation.isSensitive = kind != nil
                annotation.sensitiveReason = kind?.reason
            }
        }
        observer.changed = { [weak self] app in self?.frontWindowChanged(app) }
        var providers = intelligence.providers
        providers.fits = fits
        providers.drag = interceptor
        intelligence.providers = providers
        intelligence.slotsChanged = { [weak coordinator] in coordinator?.refreshTile() }

        let panel = coordinator.panelState
        panel.savePage = { [weak self] in self?.saveOfferedPage() }
        panel.linkRelation = { [weak self] item in self?.links.relationLine(for: item) }
        panel.conversionChip = { [weak self, weak panel] item in
            self?.interceptor.chip(for: item, context: panel?.frontmost)
        }
        panel.markNotSensitive = { [weak self] id in self?.markNotSensitive(id) }
    }

    func stop() {
        observer.stop()
        sensitive.stop()
        links.stop()
        conversions.stop()
        FlixSiteIconStore.shared.stop()
        pageTask?.cancel()
        pageTask = nil
    }

    /// Flix Files was switched off: cancels running conversions (removing their copies), the
    /// Save-this-page read, and the Fits cache. Observers, the guard, and link timers stop through
    /// ``apply(_:)``.
    func suspend() {
        conversions.stop()
        pageTask?.cancel()
        pageTask = nil
        fits.reset()
    }

    /// Starts and stops what the settings call for. Everything here is off while Flix Files is.
    func apply(_ settings: FlixSettings) {
        let enabled = settings.isEnabled
        let watchesWindows = enabled && (settings.showsFitsOnTile || settings.tracksLinks)
        if watchesWindows { observer.start() } else { observer.stop() }
        sensitive.setEnabled(enabled && settings.guardsSensitiveFiles)
        links.apply(settings)
        FlixSiteIconStore.shared.isEnabled = enabled && settings.tracksLinks && settings.fetchesSiteIcons
        if !settings.suggestsForFrontWindow && !settings.showsFitsOnTile { fits.reset() }
    }

    // MARK: Hooks from the coordinator

    func historyChanged(_ items: [FlixItem]) {
        guard let coordinator else { return }
        sensitive.update(items: items, policy: coordinator.readPolicy)
        links.historyChanged(items)
    }

    func recorded(_ events: [FlixActivityEvent]) {
        links.recorded(events)
    }

    /// The panel opened: offers **Save this page** when a browser is in front.
    func panelOpened(_ context: FlixFrontmostContext?) {
        pageTask?.cancel()
        guard let panel = coordinator?.panelState else { return }
        panel.pageOffer = nil
        guard links.isTracking, let context else { return }
        pageTask = Task { [weak self, weak panel] in
            guard let page = await self?.links.currentPage(for: context), !Task.isCancelled else { return }
            panel?.pageOffer = FlixPageOffer(page: page, isSaved: self?.isSaved(page) ?? false)
        }
    }

    /// Items were dropped outside while `context`'s app was in front.
    func dropped(_ items: [FlixItem], context: FlixFrontmostContext?) {
        links.dropped(items, context: context)
    }

    // MARK: Pieces

    /// The window in front changed: the tile's pill re-counts, and web links look at the page.
    private func frontWindowChanged(_ app: NSRunningApplication) {
        guard let coordinator, coordinator.settings.isEnabled else { return }
        links.frontWindowChanged(app)
        guard !coordinator.isPanelOpen, coordinator.settings.showsFitsOnTile else { return }
        coordinator.intelligence.frontWindowChanged(FlixFrontmostContext.capture(fallback: nil),
                                                    items: coordinator.history.items)
    }

    /// Converts ahead of a drag: the Fits rows, the selection, and the first rows of the list.
    private func prepareConversions(_ context: FlixFrontmostContext, _ demand: FlixWindowDemand, _ fitIDs: [FlixItem.ID]) {
        guard demand.hasLimits, let coordinator, coordinator.settings.isEnabled else { return }
        let panel = coordinator.panelState
        var ids = fitIDs
        if coordinator.isPanelOpen, panel.frontmost == context {
            ids += panel.navigationOrder.filter(panel.selection.contains)
            ids += panel.navigationOrder.prefix(6)
        } else if let newest = coordinator.history.newest(hidingNoise: coordinator.settings.hidesNoise) {
            // The tile's count: a drag off the tile carries the newest item.
            ids.append(newest.id)
        }
        var seen = Set<FlixItem.ID>()
        let items = ids.filter { seen.insert($0).inserted }.compactMap(coordinator.history.item)
        conversions.prepare(items, for: demand, policy: coordinator.readPolicy)
    }

    private func saveOfferedPage() {
        guard let panel = coordinator?.panelState, let offer = panel.pageOffer, !offer.isSaved else { return }
        links.save(offer.page)
        panel.pageOffer?.isSaved = true
        panel.showToast(String(localized: .flixToastPageSaved(offer.page.title ?? offer.page.host)))
    }

    private func isSaved(_ page: FlixBrowserPage) -> Bool {
        coordinator?.history.items.contains { $0.link?.url == page.url } ?? false
    }

    private func markNotSensitive(_ id: FlixItem.ID) {
        guard let coordinator, let item = coordinator.history.item(id) else { return }
        sensitive.markNotSensitive(item)
        Analytics.track(.flixSensitiveMarkedSafe(itemKind: item.analyticsKind))
        if let pending = coordinator.panelState.confirmation {
            coordinator.panelState.resolveConfirmation(.sendAnyway, ids: pending.itemIDs)
        } else {
            coordinator.approveDrop(.sensitive(itemID: id, reason: nil, destination: nil))
        }
        coordinator.panelState.showToast(String(localized: .flixToastMarkedNotSensitive(
            String(localized: .flixLabelQuoted(item.name)))))
    }
}

/// The **Save this page** card's content: the page in the browser in front.
struct FlixPageOffer: Equatable {
    var page: FlixBrowserPage
    var isSaved: Bool
}
