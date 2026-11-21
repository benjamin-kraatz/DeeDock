import Foundation
import Observation

/// The slots every ✦ surface in Flix Files reads. Inert by default.
///
/// Views read only these published values and call only these methods; they never touch a provider.
/// With ``providers`` empty (phase A), every slot keeps its empty value, so the Fits card, Threads,
/// captions, Tidy, Ask Robi, and the other AI surfaces simply do not appear, while plain filters and
/// name search keep working. Phase B installs providers in ``providers`` and the same views light
/// up.
///
/// Task ownership: each slot has at most one task in flight; starting it again cancels the old one,
/// and a generation check drops a stale result. ``panelClosed()`` cancels the panel-scoped tasks
/// (fits, query, Robi); ``stop()`` cancels everything. Main actor only.
@MainActor @Observable
final class FlixIntelligence {
    /// Phase B's providers. Assigning replaces them all and clears slots whose provider went away.
    var providers = FlixIntelligenceProviders() {
        didSet { clearMissingSlots() }
    }
    /// The Flix settings the slots obey (`suggestsForFrontWindow`, `writesCaptions`, …). With
    /// `isEnabled` off nothing runs: every task is cancelled and no pass starts.
    var settings = FlixSettings() {
        didSet {
            guard settings != oldValue else { return }
            if !settings.isEnabled { stop() }
            clearDisabledSlots()
        }
    }
    /// Settings' "What powers it" rows, kept current by `FlixEngineMonitor`.
    var engines = FlixEngineStatus()

    private(set) var fits: FlixFitsState = .hidden
    /// The tile's "✦ N fit here" pill. Nil hides it.
    private(set) var tileFitCount: Int? {
        didSet { if tileFitCount != oldValue { slotsChanged?() } }
    }
    private(set) var query: FlixQueryState = .idle
    private(set) var threads: [FlixThread] = []
    private(set) var annotations: [FlixItem.ID: FlixItemAnnotation] = [:]
    private(set) var morning: FlixMorningCard?
    private(set) var moreLikeThis: FlixMoreLikeThis? {
        didSet { if moreLikeThis != oldValue { metrics?.moreLikeThisChanged(from: oldValue, to: moreLikeThis) } }
    }
    private(set) var smartFilterDraft: FlixSmartFilterDraftState = .idle
    private(set) var tidy: [FlixTidySuggestion] = []
    private(set) var robi: FlixRobiAnswerState = .idle
    private(set) var filterTip: FlixFilterTip?
    /// A banner such as "✦ Flix noticed: PDFs go to portal.example.com".
    var notice: String?
    /// How the last plain-words search was understood, for `flix_search_ended`. Nil before one.
    private(set) var searchReport: FlixSearchReport?
    /// The open visit's tracker, set by the coordinator. Nil in previews and tests.
    @ObservationIgnored weak var metrics: FlixSessionMetrics?

    @ObservationIgnored private var fitsTask: Task<Void, Never>?
    @ObservationIgnored private var tileTask: Task<Void, Never>?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var likeTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var tidyTask: Task<Void, Never>?
    @ObservationIgnored private var robiTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastMorningDay: Date?
    /// Phase B1: the tile's pill or an annotation the tile draws (the sensitive blur) changed. The
    /// coordinator redraws the tile; the tile is not a SwiftUI observer of this model.
    @ObservationIgnored var slotsChanged: (() -> Void)?

    init() {}

    // MARK: Capabilities the UI asks about

    var searchesInPlainWords: Bool { providers.search != nil }
    var searchExamples: [String] { providers.search?.examples ?? [] }
    var canTidy: Bool { providers.tidy != nil }
    var canGenerateSmartFilters: Bool { providers.smartFilters != nil }
    var smartFilterExamples: [String] { providers.smartFilters?.examples ?? [] }
    var canAskRobi: Bool { providers.robi?.isReady == true }
    /// Ask Robi answers on this Mac (Robi's settings choose the on-device model).
    var robiAnswersOnDevice: Bool { providers.robi?.answersOnDevice ?? false }
    var canShowMoreLikeThis: Bool { providers.similarity != nil }
    var hasThreads: Bool { settings.groupsThreads && !threads.isEmpty }
    /// Lookout runs and answers searches by meaning (from ``engines``).
    var lookoutAvailable: Bool { if case .ready = engines.lookout { true } else { false } }

    func annotation(for id: FlixItem.ID) -> FlixItemAnnotation? {
        settings.writesCaptions || settings.guardsSensitiveFiles ? annotations[id] : nil
    }

    func thread(_ id: String) -> FlixThread? { threads.first { $0.id == id } }

    /// The Thread an item belongs to, for "Show Thread".
    func thread(containing id: FlixItem.ID) -> FlixThread? {
        guard settings.groupsThreads else { return nil }
        return threads.first { $0.memberIDs.contains(id) }
    }

    func robiQuestions(for items: [FlixItem]) -> [String] { providers.robi?.questions(for: items) ?? [] }

    /// Answers a Smart Filter `.about` rule from the similarity cache.
    func semanticMatch(topic: String, item: FlixItem) -> Bool? {
        providers.similarity?.cachedMatch(topic: topic, item: item)
    }

    func dragReason(for item: FlixItem, context: FlixFrontmostContext?) -> FlixDragReason? {
        guard settings.learnsDragDestinations else { return nil }
        return providers.dragMemory?.reason(for: item, context: context)
    }

    /// The item drag memory expects the app in front to want, for ranking the Fits card.
    func likelyItem(for context: FlixFrontmostContext?, among items: [FlixItem]) -> FlixItem.ID? {
        guard settings.learnsDragDestinations else { return nil }
        return providers.dragMemory?.likelyItem(for: context, among: items)
    }

    // MARK: Panel lifecycle

    /// The panel opened. Reads the window in front (once), and asks for a morning card on the first
    /// open of a day.
    func panelOpened(context: FlixFrontmostContext?, items: [FlixItem], now: Date = .now) {
        generation += 1
        readWindow(context: context, items: items)
        if let provider = providers.morning, lastMorningDay.map({ !Calendar.current.isDate($0, inSameDayAs: now) }) ?? true {
            lastMorningDay = now
            let threads = threads
            let token = generation
            Task { [weak self] in
                let card = await provider.morningCard(items: items, threads: threads, now: now)
                guard let self, generation == token else { return }
                morning = card
            }
        }
        if settings.learnsDragDestinations { filterTip = providers.dragMemory?.filterTip(items: items, now: now) }
    }

    /// The panel closed: cancels work only the panel could show.
    func panelClosed() {
        generation += 1
        fitsTask?.cancel(); fitsTask = nil
        queryTask?.cancel(); queryTask = nil
        likeTask?.cancel(); likeTask = nil
        filterTask?.cancel(); filterTask = nil
        tidyTask?.cancel(); tidyTask = nil
        robiTask?.cancel(); robiTask = nil
        fits = .hidden
        query = .idle
        moreLikeThis = nil
        smartFilterDraft = .idle
        robi = .idle
    }

    private func readWindow(context: FlixFrontmostContext?, items: [FlixItem]) {
        fitsTask?.cancel()
        guard settings.suggestsForFrontWindow, let provider = providers.fits, let context else {
            fits = .hidden
            return
        }
        let token = generation
        fits = .reading(windowLabel: context.applicationName ?? "", chain: FlixReaderChain())
        fitsTask = Task { [weak self] in
            let result = await provider.fits(for: context, candidates: items) { label, chain in
                guard let self, self.generation == token, case .reading = self.fits else { return }
                self.fits = .reading(windowLabel: label, chain: chain)
            }
            guard let self, generation == token, !Task.isCancelled else { return }
            fits = result.map { .ready(self.withMemory($0, context: context, items: items)) } ?? .hidden
        }
    }

    /// Adds drag memory's "↺ you've sent PDFs here before" to fits that lack a reason.
    private func withMemory(_ result: FlixFitsResult, context: FlixFrontmostContext, items: [FlixItem]) -> FlixFitsResult {
        var result = result
        for index in result.fits.indices where result.fits[index].memory == nil {
            let id = result.fits[index].itemID
            result.fits[index].memory = items.first { $0.id == id }.flatMap { dragReason(for: $0, context: context) }
        }
        return result
    }

    /// The window in front changed while the panel is closed: refreshes the tile pill.
    func frontWindowChanged(_ context: FlixFrontmostContext?, items: [FlixItem]) {
        tileTask?.cancel()
        guard settings.isEnabled, settings.showsFitsOnTile, let provider = providers.fits, let context else {
            tileFitCount = nil
            return
        }
        tileTask = Task { [weak self] in
            let count = await provider.tileFitCount(for: context, candidates: items)
            guard let self, !Task.isCancelled else { return }
            tileFitCount = count.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// The history changed. Refreshes annotations and threads in the background, coalesced. Does
    /// nothing while Flix Files is off.
    func historyChanged(items: [FlixItem]) {
        guard settings.isEnabled, providers.annotations != nil || providers.threads != nil else { return }
        backgroundTask?.cancel()
        let annotations = providers.annotations
        let threads = settings.groupsThreads ? providers.threads : nil
        let known = self.annotations
        backgroundTask = Task { [weak self] in
            // Coalesces bursts, such as a Spotlight gather, into one pass.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.settings.isEnabled == true else { return }
            if let annotations {
                let fresh = await annotations.annotations(for: items, known: known)
                guard let self, !Task.isCancelled else { return }
                // The sensitive fields belong to phase B1's guard (`reviseAnnotation`); a fresh
                // annotation from another provider keeps them.
                self.annotations.merge(fresh) { old, new in
                    var merged = new
                    merged.isSensitive = old.isSensitive
                    merged.sensitiveReason = old.sensitiveReason
                    return merged
                }
            }
            if let threads {
                let groups = await threads.threads(for: items)
                guard let self, !Task.isCancelled else { return }
                self.threads = groups
            }
        }
    }

    /// Changes one item's annotation in place, creating it when missing. Phase B1's sensitive guard
    /// writes its verdicts through here as they arrive, outside the coalesced provider pass.
    func reviseAnnotation(for id: FlixItem.ID, _ change: (inout FlixItemAnnotation) -> Void) {
        var annotation = annotations[id] ?? FlixItemAnnotation()
        let before = annotation
        change(&annotation)
        guard annotation != before else { return }
        annotations[id] = annotation
        slotsChanged?()
    }

    /// Forgets annotations for items no longer in the history.
    func prune(keeping ids: Set<FlixItem.ID>) {
        annotations = annotations.filter { ids.contains($0.key) }
    }

    // MARK: Search

    /// Understands `text` when a provider can. Callers debounce typing.
    func understand(_ text: String, items: [FlixItem], now: Date = .now) {
        queryTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider = providers.search, !trimmed.isEmpty else {
            query = .idle
            return
        }
        query = .understanding
        queryTask = Task { [weak self] in
            let result = await provider.understand(trimmed, items: items, now: now)
            guard let self, !Task.isCancelled else { return }
            searchReport = provider.lastReport
            query = result.map { .understood(tokens: $0.tokens, matches: $0.matches) } ?? .idle
        }
    }

    /// Removes one understood token; the search widens.
    func removeToken(_ id: FlixQueryToken.ID) {
        guard case .understood(var tokens, _) = query else { return }
        if let removed = tokens.first(where: { $0.id == id }) { metrics?.searchTokenRemoved(removed.rule.analyticsTokenType) }
        tokens.removeAll { $0.id == id }
        query = tokens.isEmpty ? .idle : .understood(tokens: tokens, matches: nil)
    }

    func clearQuery() {
        queryTask?.cancel()
        query = .idle
    }

    // MARK: More like this

    func showMoreLikeThis(_ item: FlixItem, in items: [FlixItem]) {
        likeTask?.cancel()
        guard let provider = providers.similarity else { return }
        moreLikeThis = FlixMoreLikeThis(sourceID: item.id, resultIDs: nil)
        likeTask = Task { [weak self] in
            let ids = await provider.similar(to: item, in: items)
            guard let self, !Task.isCancelled, moreLikeThis?.sourceID == item.id else { return }
            moreLikeThis = FlixMoreLikeThis(sourceID: item.id, resultIDs: ids)
        }
    }

    func clearMoreLikeThis() {
        likeTask?.cancel()
        moreLikeThis = nil
    }

    // MARK: Smart Filters, Tidy, Ask Robi

    func generateSmartFilter(from sentence: String, items: [FlixItem]) {
        filterTask?.cancel()
        guard let provider = providers.smartFilters else { return }
        smartFilterDraft = .generating
        filterTask = Task { [weak self] in
            let proposal = await provider.proposal(for: sentence, items: items)
            guard let self, !Task.isCancelled else { return }
            smartFilterDraft = proposal.map(FlixSmartFilterDraftState.ready) ?? .failed
        }
    }

    func resetSmartFilterDraft() {
        filterTask?.cancel()
        smartFilterDraft = .idle
    }

    func refreshTidy(items: [FlixItem]) {
        tidyTask?.cancel()
        guard let provider = providers.tidy else { tidy = []; return }
        let annotations = annotations
        tidyTask = Task { [weak self] in
            let suggestions = await provider.suggestions(for: items, annotations: annotations)
            guard let self, !Task.isCancelled else { return }
            tidy = suggestions
        }
    }

    /// Asks Robi. `token` says which question it was (a suggestion's position or typed) for
    /// `flix_robi_asked`, which reports only that, the selection's kinds, the latency, and the result.
    func ask(_ question: String, about items: [FlixItem], question token: AnalyticsFlixRobiQuestion = .typed) {
        robiTask?.cancel()
        guard let provider = providers.robi, !items.isEmpty else { return }
        robi = .answering(question: question, text: "")
        let started = ContinuousClock.now
        let report = { (result: AnalyticsFlixRobiResult) in
            Analytics.track(.flixRobiAsked(AnalyticsFlixRobi(
                question: token, selectionCount: items.count, itemKinds: items.analyticsKinds,
                latencyMs: Int((ContinuousClock.now - started) / .milliseconds(1)), result: result)))
        }
        robiTask = Task { [weak self] in
            var text = ""
            do {
                for try await chunk in provider.answer(question, about: items) {
                    guard !Task.isCancelled else { return report(.cancelled) }
                    text += chunk
                    self?.robi = .answering(question: question, text: text)
                }
                // A cancelled stream ends quietly instead of throwing.
                guard !Task.isCancelled else { return report(.cancelled) }
                self?.robi = .answered(question: question, text: text)
                report(.answered)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return report(.cancelled) }
                if case FlixRobiProvider.Failure.needsKey = error { report(.noKey) } else { report(.failed) }
                self?.robi = .failed(question: question, message: error.localizedDescription)
            }
        }
    }

    func resetRobi() {
        robiTask?.cancel()
        robi = .idle
    }

    func dismissMorning() { morning = nil }

    func dismissFilterTip() { filterTip = nil }

    // MARK: Drag hooks

    /// What a drag of `items` should carry. Synchronous; see ``FlixDragIntercepting``.
    func dragPlan(for items: [FlixItem], context: FlixFrontmostContext?) -> FlixDragPlan? {
        let result: FlixFitsResult? = if case .ready(let result) = fits { result } else { nil }
        return providers.drag?.plan(for: items, context: context, fits: result)
    }

    /// The question to ask before `items` leave for another app, or nil.
    ///
    /// Phase A's own rules run when no provider answers: an annotated sensitive item (while the
    /// sensitive guard is on), then an older version of a document with a newer one in the history.
    /// With a drag provider installed (phase B1), the provider alone decides the sensitive question,
    /// because it asks only for outside targets (a browser, mail, a chat).
    func dropConfirmation(for items: [FlixItem], context: FlixFrontmostContext?) -> FlixDropConfirmation? {
        if let answer = providers.drag?.confirmation(for: items, context: context) { return answer }
        if settings.guardsSensitiveFiles, providers.drag == nil,
           let sensitive = items.first(where: { annotations[$0.id]?.isSensitive == true }) {
            return .sensitive(itemID: sensitive.id, reason: annotations[sensitive.id]?.sensitiveReason,
                              destination: context?.applicationName)
        }
        for item in items {
            guard let annotation = annotations[item.id], let group = annotation.versionGroup,
                  let rank = annotation.versionRank else { continue }
            let newer = annotations
                .filter { $0.value.versionGroup == group && ($0.value.versionRank ?? .min) > rank }
                .max { ($0.value.versionRank ?? 0) < ($1.value.versionRank ?? 0) }
            if let newer, !items.contains(where: { $0.id == newer.key }) {
                return .newerVersion(itemID: item.id, newerID: newer.key)
            }
        }
        return nil
    }

    /// Items were dropped outside Flix Files. Drag memory learns from it.
    func recordDrop(of items: [FlixItem], context: FlixFrontmostContext?) {
        guard settings.learnsDragDestinations, let message = providers.dragMemory?.recordDrop(of: items, context: context)
        else { return }
        notice = message
    }

    func forgetDragMemory() { providers.dragMemory?.forget() }

    // MARK: Teardown

    func stop() {
        panelClosed()
        tileTask?.cancel(); tileTask = nil
        backgroundTask?.cancel(); backgroundTask = nil
        tileFitCount = nil
    }

    /// Whether a coalesced annotation and Threads pass was scheduled and not cancelled since (it
    /// stays set once it finished). For tests of the master switch.
    var isBackgroundPassPending: Bool { backgroundTask != nil }

    #if DEBUG
    /// Fills slots directly, for previews. Never called in a running app.
    func applyPreview(fits: FlixFitsState = .hidden, threads: [FlixThread] = [],
                      annotations: [FlixItem.ID: FlixItemAnnotation] = [:], morning: FlixMorningCard? = nil,
                      tidy: [FlixTidySuggestion] = [], filterTip: FlixFilterTip? = nil,
                      query: FlixQueryState = .idle, moreLikeThis: FlixMoreLikeThis? = nil,
                      smartFilterDraft: FlixSmartFilterDraftState = .idle, robi: FlixRobiAnswerState = .idle) {
        self.fits = fits
        self.threads = threads
        self.annotations = annotations
        self.morning = morning
        self.tidy = tidy
        self.filterTip = filterTip
        self.query = query
        self.moreLikeThis = moreLikeThis
        self.smartFilterDraft = smartFilterDraft
        self.robi = robi
    }
    #endif

    private func clearMissingSlots() {
        if providers.fits == nil { fits = .hidden; tileFitCount = nil }
        if providers.search == nil { query = .idle }
        if providers.threads == nil { threads = [] }
        if providers.annotations == nil { annotations = [:] }
        if providers.morning == nil { morning = nil }
        if providers.similarity == nil { moreLikeThis = nil }
        if providers.smartFilters == nil { smartFilterDraft = .idle }
        if providers.tidy == nil { tidy = [] }
        if providers.robi == nil { robi = .idle }
        if providers.dragMemory == nil { filterTip = nil }
    }

    private func clearDisabledSlots() {
        if !settings.suggestsForFrontWindow { fits = .hidden }
        if !settings.showsFitsOnTile { tileFitCount = nil }
        if !settings.learnsDragDestinations { filterTip = nil }
    }
}
