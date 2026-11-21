import AppKit

/// "Fits this window": reads the window that was in front when the panel opened, works out what it
/// asks for, and picks up to three history items for it. Also the tile's "✦ N fit here" count.
///
/// - **Reading** (panel only): ``FlixWindowReader``'s chain, Accessibility → Vision → Apple
///   Intelligence, once per open.
/// - **Understanding**: Apple Intelligence turns the text (or the picture) into a
///   ``FlixWindowDemand``; without it, or when it fails or times out, ``FlixDemandFallbackParser``.
///   The tile never uses a model or a capture: Accessibility text and the plain rules only.
/// - **Matching**: ``FlixFitRanker`` with a ``FlixFitScoring`` (keyword overlap today; Lookout's
///   embeddings can replace it behind the same protocol).
///
/// Readings are cached per ``FlixWindowKey`` (app, window number, accessibility title), so opening
/// the panel again on the same window only re-ranks, and a new page or conversation reads afresh.
/// The cache holds the newest 24 windows. Main actor; reading and ranking run off it. Cancellation
/// comes from `FlixIntelligence`, which cancels the task when the panel closes or opens again.
@MainActor
final class FlixFitsProvider: FlixFitsProviding {
    private struct Entry {
        var demand: FlixWindowDemand
        var chain: FlixReaderChain
        var label: String
        /// False for the tile's Accessibility-only reading, which the panel replaces.
        var isComplete: Bool
        var date: Date
    }

    private let reader: FlixWindowReader
    private let scorer: any FlixFitScoring
    private var cache: [FlixWindowKey: Entry] = [:]
    /// The newest key per app and window, so the drag hooks can find a window's demand without
    /// another accessibility read.
    private var latest: [WindowRef: FlixWindowKey] = [:]

    /// Captions and noise verdicts from phase B's annotations, by item.
    var annotation: (FlixItem.ID) -> FlixItemAnnotation? = { _ in nil }
    /// The page in a browser window, for the card's label ("Fits portal.example.com").
    var browserPage: (FlixFrontmostContext) async -> FlixBrowserPage? = { _ in nil }
    /// A window's demand is known, with the items picked for it. Conversions are prepared here.
    var demandReady: ((FlixFrontmostContext, FlixWindowDemand, [FlixItem.ID]) -> Void)?

    init(scorer: any FlixFitScoring = FlixKeywordFitScorer()) {
        reader = FlixWindowReader()
        self.scorer = scorer
    }

    // MARK: FlixFitsProviding

    func fits(for context: FlixFrontmostContext, candidates: [FlixItem],
              progress: @escaping @MainActor (String, FlixReaderChain) -> Void) async -> FlixFitsResult? {
        let key = await reader.key(for: context)
        guard !Task.isCancelled else { return nil }
        let entry: Entry
        if let cached = cache[key], cached.isComplete {
            entry = cached
        } else {
            var label = Self.label(for: context, title: key.title)
            progress(label, FlixReaderChain())
            if let page = await browserPage(context) { label = page.host }
            guard !Task.isCancelled else { return nil }
            let reading = await reader.read(context) { chain in progress(label, chain) }
            guard !Task.isCancelled else { return nil }
            let demand = await interpret(reading, context: context)
            guard !Task.isCancelled else { return nil }
            entry = Entry(demand: demand, chain: reading.chain, label: label, isComplete: true, date: .now)
            store(entry, for: key)
        }
        let ranked = await rank(entry.demand, candidates: candidates)
        guard !Task.isCancelled else { return nil }
        demandReady?(context, entry.demand, ranked.map(\.itemID))
        guard !ranked.isEmpty else { return nil }
        return FlixFitsResult(windowLabel: entry.label, chain: entry.chain,
                              fits: ranked.map { FlixFit(itemID: $0.itemID, phrase: $0.phrase) },
                              intent: entry.demand.intent)
    }

    func tileFitCount(for context: FlixFrontmostContext, candidates: [FlixItem]) async -> Int? {
        let key = await reader.key(for: context)
        guard !Task.isCancelled else { return nil }
        let demand: FlixWindowDemand
        if let cached = cache[key] {
            demand = cached.demand
        } else {
            let text = await reader.accessibilityText(for: context)
            guard !Task.isCancelled else { return nil }
            demand = FlixDemandFallbackParser.parse(text, pageKind: Self.pageKind(for: context))
            store(Entry(demand: demand, chain: FlixReaderChain(steps: [.accessibility], succeeded: true),
                        label: Self.label(for: context, title: key.title), isComplete: false, date: .now), for: key)
        }
        let ranked = await rank(demand, candidates: candidates)
        guard !Task.isCancelled else { return nil }
        demandReady?(context, demand, ranked.map(\.itemID))
        return ranked.isEmpty ? nil : ranked.count
    }

    // MARK: For the drag hooks

    /// The newest known demand for the window `context` names. Synchronous, from the cache.
    func demand(for context: FlixFrontmostContext?) -> FlixWindowDemand? {
        guard let context, let key = latest[WindowRef(context)] else { return nil }
        return cache[key]?.demand
    }

    /// The card's name for the window `context` names ("portal.example.com", "Mail · Review"), from
    /// the cache.
    func windowLabel(for context: FlixFrontmostContext?) -> String? {
        guard let context, let key = latest[WindowRef(context)] else { return nil }
        return cache[key]?.label
    }

    /// Forgets every reading, for when Settings turn suggestions off.
    func reset() {
        cache = [:]
        latest = [:]
    }

    // MARK: Pieces

    private func interpret(_ reading: FlixWindowReading, context: FlixFrontmostContext) async -> FlixWindowDemand {
        let kind = Self.pageKind(for: context)
        var demand: FlixWindowDemand?
        if let image = reading.image {
            demand = await FlixDemandInterpreter.demand(fromImage: FlixSendableImage(image: image), appName: context.applicationName)
        } else if FlixWindowTextPolicy.isEnough(reading.text) {
            demand = await FlixDemandInterpreter.demand(fromText: reading.text, appName: context.applicationName)
        }
        var result = demand ?? FlixDemandFallbackParser.parse(reading.text, pageKind: kind)
        if result.pageKind == .other { result.pageKind = kind }
        return result
    }

    private func rank(_ demand: FlixWindowDemand, candidates items: [FlixItem]) async -> [FlixFitRanker.Ranked] {
        guard !demand.wanted.isEmpty else { return [] }
        let candidates = items.prefix(FlixFitRanker.candidateLimit).compactMap { item -> FlixFitCandidate? in
            let annotation = annotation(item.id)
            if annotation?.isNoise ?? FlixNoiseRules.isNoise(path: item.path) { return nil }
            return FlixFitCandidate(item: item, caption: annotation?.caption, facts: annotation?.facts.map(\.text) ?? [])
        }
        let scorer = scorer
        return await Task.detached(priority: .userInitiated) {
            FlixFitRanker.rank(demand: demand, candidates: candidates, scorer: scorer, now: .now)
        }.value
    }

    private func store(_ entry: Entry, for key: FlixWindowKey) {
        cache[key] = entry
        latest[WindowRef(processIdentifier: key.processIdentifier, windowID: key.windowID)] = key
        if cache.count > 24, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key {
            cache[oldest] = nil
        }
    }

    /// "Mail · Packaging review", or the app's name alone.
    static func label(for context: FlixFrontmostContext, title: String?) -> String {
        let app = context.applicationName ?? ""
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty, title != app else { return app }
        return app.isEmpty ? title : app + " · " + title
    }

    static func pageKind(for context: FlixFrontmostContext) -> FlixWindowDemand.PageKind {
        switch FlixAppCategory.of(context) {
        case .mail: .mail
        case .chat: .chat
        case .office, .design: .document
        default: .other
        }
    }

    private struct WindowRef: Hashable {
        var processIdentifier: pid_t
        var windowID: CGWindowID?

        init(processIdentifier: pid_t, windowID: CGWindowID?) {
            self.processIdentifier = processIdentifier
            self.windowID = windowID
        }

        init(_ context: FlixFrontmostContext) {
            self.init(processIdentifier: context.processIdentifier, windowID: context.windowID)
        }
    }
}
