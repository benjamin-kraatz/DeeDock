import AppKit

/// "Fits this window": reads the window that was in front when the panel opened, works out what it
/// asks for, and picks up to three history items for it. Also the tile's "✦ N fit here" count.
///
/// - **Reading** (panel only): ``FlixWindowReader``'s chain, Accessibility → Vision → Apple
///   Intelligence, once per open.
/// - **Understanding**: Apple Intelligence turns the text (or the picture) into a
///   ``FlixWindowDemand``; without it, or when it fails or times out, ``FlixDemandFallbackParser``.
///   The tile never uses a model or a capture: Accessibility text and the plain rules only.
/// - **Matching**: ``FlixFitRanker`` with ``FlixKeywordFitScorer``; for the panel, while Lookout runs,
///   ``FlixBlendedFitScorer`` adds meaning from Lookout's vectors (``semantic``). Drag memory's guess
///   (``likelyItem``) wins ties. The tile's count matches words only: it never runs a model.
/// - **Reporting**: each panel reading ends with ``computed`` (`flix_fits_computed`: reader, word
///   counts, what the window asked for, matches, time), and the time the window read took goes to
///   the `flix_window_read_ms_*` counters. Never the text.
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
        var reader: AnalyticsFlixReader = .accessibility
        var accessibilityWords = 0
        var recognizedWords = 0
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
    /// Lookout, for matching by meaning. Nil (or Lookout off) matches words only.
    var semantic: FlixSemanticIndex?
    /// Drag memory's guess for the window in front, which wins ties.
    var likelyItem: (FlixFrontmostContext, [FlixItem]) -> FlixItem.ID? = { _, _ in nil }
    /// A panel reading finished, with what `flix_fits_computed` reports.
    var computed: ((AnalyticsFlixFits) -> Void)?

    init(scorer: any FlixFitScoring = FlixKeywordFitScorer()) {
        reader = FlixWindowReader()
        self.scorer = scorer
    }

    // MARK: FlixFitsProviding

    func fits(for context: FlixFrontmostContext, candidates: [FlixItem],
              progress: @escaping @MainActor (String, FlixReaderChain) -> Void) async -> FlixFitsResult? {
        let started = ContinuousClock.now
        let key = await reader.key(for: context)
        guard !Task.isCancelled else { return nil }
        let entry: Entry
        if let cached = cache[key], cached.isComplete {
            entry = cached
            // The window's reading and Apple Intelligence's interpretation are reused.
            Analytics.count(.aiCacheHits)
        } else {
            var label = Self.label(for: context, title: key.title)
            progress(label, FlixReaderChain())
            if let page = await browserPage(context) { label = page.host }
            guard !Task.isCancelled else { return nil }
            let readStarted = ContinuousClock.now
            let reading = await reader.read(context) { chain in progress(label, chain) }
            guard !Task.isCancelled else { return nil }
            Analytics.countTiming(sum: .windowReadSum, count: .windowReadCount, max: .windowReadMax,
                                  milliseconds: Self.milliseconds(since: readStarted))
            let demand = await interpret(reading, context: context)
            guard !Task.isCancelled else { return nil }
            entry = Entry(demand: demand, chain: reading.chain, label: label, isComplete: true, date: .now,
                          reader: Self.reader(for: reading), accessibilityWords: reading.accessibilityWords,
                          recognizedWords: reading.recognizedWords)
            store(entry, for: key)
        }
        let ranked = await rank(entry.demand, candidates: candidates, context: context, byMeaning: true)
        guard !Task.isCancelled else { return nil }
        demandReady?(context, entry.demand, ranked.map(\.itemID))
        report(entry, context: context, matches: ranked.count, readyMs: Self.milliseconds(since: started))
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
        let ranked = await rank(demand, candidates: candidates, context: context, byMeaning: false)
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

    /// Ranks the candidates for `demand`. `byMeaning` adds Lookout's meaning scores, which costs one
    /// text embedding per wanted phrase; the tile's count passes false.
    private func rank(_ demand: FlixWindowDemand, candidates items: [FlixItem], context: FlixFrontmostContext,
                      byMeaning: Bool) async -> [FlixFitRanker.Ranked] {
        guard !demand.wanted.isEmpty else { return [] }
        let candidates = items.prefix(FlixFitRanker.candidateLimit).compactMap { item -> FlixFitCandidate? in
            let annotation = annotation(item.id)
            if annotation?.isNoise ?? FlixNoiseRules.isNoise(path: item.path) { return nil }
            return FlixFitCandidate(item: item, caption: annotation?.caption, facts: annotation?.facts.map(\.text) ?? [])
        }
        let meaning = byMeaning ? await meaningScores(for: demand, candidates: candidates) : [:]
        guard !Task.isCancelled else { return [] }
        let scorer: any FlixFitScoring = meaning.isEmpty ? scorer : FlixBlendedFitScorer(keyword: scorer, meaning: meaning)
        let preferred = likelyItem(context, candidates.map(\.item))
        return await Task.detached(priority: .userInitiated) {
            FlixFitRanker.rank(demand: demand, candidates: candidates, scorer: scorer, now: .now, preferred: preferred)
        }.value
    }

    /// Lookout's meaning scores by wanted phrase and item: only files whose text-averaged vector
    /// stands out from the rest. Empty while Lookout is off or has no vectors for these files.
    private func meaningScores(for demand: FlixWindowDemand, candidates: [FlixFitCandidate]) async
        -> [String: [FlixItem.ID: Double]] {
        guard let semantic, semantic.isAvailable else { return [:] }
        let vectors = await semantic.vectors(for: candidates.compactMap(\.item.path))
        let pool = candidates.compactMap { candidate -> (id: FlixItem.ID, vector: [Float])? in
            guard let path = candidate.item.path, let vector = vectors[path], !vector.isPicture else { return nil }
            return (candidate.item.id, vector.vector)
        }
        guard !pool.isEmpty else { return [:] }
        var scores: [String: [FlixItem.ID: Double]] = [:]
        for wanted in demand.wanted where scores[wanted.phrase] == nil {
            guard !Task.isCancelled, let query = await semantic.embed(wanted.phrase) else { continue }
            let ranked = FlixSemanticScoring.ranked(query, against: pool, floor: FlixBlendedFitScorer.floor,
                                                    minimumZ: FlixBlendedFitScorer.minimumZ, limit: 12)
            scores[wanted.phrase] = Dictionary(ranked.map { ($0.id, FlixBlendedFitScorer.normalized($0.score)) },
                                               uniquingKeysWith: { Swift.max($0, $1) })
        }
        return scores
    }

    /// Sends one panel reading's `flix_fits_computed`.
    private func report(_ entry: Entry, context: FlixFrontmostContext, matches: Int, readyMs: Int) {
        let category = FlixAppCategory.of(context)
        let demand = entry.demand
        computed?(AnalyticsFlixFits(
            reader: entry.reader, stepsTried: entry.chain.steps.count, axWords: entry.accessibilityWords,
            ocrWords: entry.recognizedWords, intentItems: demand.wanted.count, hasTypeLimit: !demand.acceptedTypes.isEmpty,
            hasSizeLimit: demand.maximumBytes != nil, matches: matches, readyMs: readyMs, frontCategory: category,
            pageKind: category == .browser ? AnalyticsFlixPageKind(demand.pageKind) : nil))
    }

    /// Which reader produced the text: the step that succeeded, the picture for Apple Intelligence,
    /// none when every step found too little, or no permission when no step could run.
    static func reader(for reading: FlixWindowReading) -> AnalyticsFlixReader {
        guard let last = reading.chain.steps.last else { return .noPermission }
        if last == .appleIntelligence, reading.image != nil { return .appleIntelligenceImage }
        guard reading.chain.succeeded else { return .none }
        switch last {
        case .accessibility: return .accessibility
        case .vision: return .vision
        case .appleIntelligence: return .appleIntelligenceImage
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
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
