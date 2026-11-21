import AppKit

// Provider protocols phase B implements. Phase A ships none, so every slot in `FlixIntelligence`
// stays inert and its surface does not appear. All providers are main-actor objects: they take
// value snapshots, do heavy work off the main actor themselves, and hand values back. None may run
// work from a pointer or drag path except the synchronous drag hooks, which must answer from caches.

/// Context captured right before the Flix panel took focus: the app and window that were in front.
///
/// Phase B1 reads the window with it ("Fits this window"); drag memory keys on it. Captured once per
/// open by `FlixCoordinator` (see ``FlixFrontmostContext/capture(excluding:)``).
nonisolated struct FlixFrontmostContext: Equatable, Sendable {
    var processIdentifier: pid_t
    var bundleIdentifier: String?
    /// Supplied by macOS; never translated.
    var applicationName: String?
    /// The frontmost on-screen window of that app, when the window server reports one.
    var windowID: CGWindowID?
    /// Nil without Screen Recording permission.
    var windowTitle: String?
    var capturedAt: Date
}

/// Reads the window in front and suggests items for it ("✦ Fits …").
@MainActor protocol FlixFitsProviding: AnyObject {
    /// Reads `context`'s window (Accessibility → Vision → Apple Intelligence) and picks fitting items.
    /// Called once per panel open; cache by window until it changes. `progress` reports each reader
    /// as it starts, so the card's chain label animates. Return nil when the window asks for nothing.
    func fits(for context: FlixFrontmostContext, candidates: [FlixItem],
              progress: @escaping @MainActor (String, FlixReaderChain) -> Void) async -> FlixFitsResult?

    /// The tile's "✦ N fit here" count: Accessibility text only, on window switch, never a capture.
    func tileFitCount(for context: FlixFrontmostContext, candidates: [FlixItem]) async -> Int?
}

/// Understands sentences typed into search ("contract Mike sent last week").
@MainActor protocol FlixSearchProviding: AnyObject {
    /// Example sentences for "Ask in your own words".
    var examples: [String] { get }
    /// Tokens for `text`, and optional per-item matches when searching by meaning.
    func understand(_ text: String, items: [FlixItem], now: Date) async
        -> (tokens: [FlixQueryToken], matches: [FlixItem.ID: FlixMatchKind]?)?
    /// How the most recent ``understand(_:items:now:)`` went, read right after it returns. Nil when
    /// the provider does not say.
    var lastReport: FlixSearchReport? { get }
}

/// How one plain-words search was understood, for analytics: which parser answered, how long it
/// took, and whether Lookout could match by meaning. No text.
nonisolated struct FlixSearchReport: Equatable, Sendable {
    var parser: AnalyticsFlixParser
    var parseMs: Int
    var lookoutAvailable: Bool
}

/// Groups activity into Threads.
@MainActor protocol FlixThreadProviding: AnyObject {
    func threads(for items: [FlixItem]) async -> [FlixThread]
}

/// Captions, renames, facts, folder suggestions, the sensitive check, versions, and learned noise.
@MainActor protocol FlixAnnotationProviding: AnyObject {
    /// New or changed annotations for `items`. `known` holds what was returned before; providers
    /// cache by content and return only what changed.
    func annotations(for items: [FlixItem], known: [FlixItem.ID: FlixItemAnnotation]) async
        -> [FlixItem.ID: FlixItemAnnotation]
}

/// The morning "Where were you?" card.
@MainActor protocol FlixMorningProviding: AnyObject {
    /// Called on the first open of a day. Nil shows nothing.
    func morningCard(items: [FlixItem], threads: [FlixThread], now: Date) async -> FlixMorningCard?
}

/// More like this, and the semantic half of Smart Filter rules.
@MainActor protocol FlixSimilarityProviding: AnyObject {
    func similar(to item: FlixItem, in items: [FlixItem]) async -> [FlixItem.ID]
    /// Answers a `.about(topic)` rule from a cache, or nil to fall back to words. Synchronous: it
    /// runs for every item on every list build.
    func cachedMatch(topic: String, item: FlixItem) -> Bool?
}

/// Smart Filters from a sentence.
@MainActor protocol FlixSmartFilterGenerating: AnyObject {
    var examples: [String] { get }
    func proposal(for sentence: String, items: [FlixItem]) async -> FlixSmartFilterProposal?
}

/// The Tidy sheet's renames and moves.
@MainActor protocol FlixTidyProviding: AnyObject {
    func suggestions(for items: [FlixItem], annotations: [FlixItem.ID: FlixItemAnnotation]) async
        -> [FlixTidySuggestion]
}

/// Ask Robi about files. Sends the files you asked about with your question, with your key; and
/// nothing else. Must opt the call out of AI observability content capture.
@MainActor protocol FlixRobiProviding: AnyObject {
    /// Robi can answer, or can at least say what is missing (a Claude key). False hides Ask Robi.
    var isReady: Bool { get }
    /// Robi's settings choose the on-device model, so nothing leaves the Mac; the sheet's privacy
    /// line says so.
    var answersOnDevice: Bool { get }
    /// Suggested questions for these items.
    func questions(for items: [FlixItem]) -> [String]
    /// Streams the answer as growing text.
    func answer(_ question: String, about items: [FlixItem]) -> AsyncThrowingStream<String, Error>
}

/// Learns where you drag things, on this Mac only.
@MainActor protocol FlixDragMemoryProviding: AnyObject {
    /// Why `item` suits the window in front, from earlier drops. Synchronous and cached.
    func reason(for item: FlixItem, context: FlixFrontmostContext?) -> FlixDragReason?
    /// Records a drop. Returns a banner message the first time a pattern is noticed.
    func recordDrop(of items: [FlixItem], context: FlixFrontmostContext?) -> String?
    /// A Smart Filter tip for the sidebar, or nil.
    func filterTip(items: [FlixItem], now: Date) -> FlixFilterTip?
    /// The item most likely wanted by the app in front, from earlier drops: the newest of the kind
    /// usually sent there. A ranking hint for the Fits card (phase B1). Synchronous and cached.
    func likelyItem(for context: FlixFrontmostContext?, among items: [FlixItem]) -> FlixItem.ID?
    /// Settings' **Forget**.
    func forget()
    /// Flix Pick: the paths picked in `app`'s (a bundle identifier) Open and Save pickers. Empty
    /// while learning is off.
    func pickerPicks(for app: String) -> [String: FlixPickMemory.Entry]
    /// Flix Pick: counts a pick of `path` in `app`'s picker. Ignored while learning is off.
    func recordPickerPick(_ path: String, isFolder: Bool, app: String)
    /// Flix Pick: forgets a picked path that is gone.
    func forgetPickerPick(_ path: String, app: String)
    /// Drops on `destination` by kind (``FlixDragMemory/kindClass(of:)``). Empty while learning is off.
    func dropCounts(for destination: String) -> [String: Int]
}

/// Hooks phase B1 uses to change a drag before it leaves Flix Files.
///
/// macOS does not tell a drag source which app it will be dropped on, so both hooks run at drag
/// start and treat the captured front window (``FlixFrontmostContext``) as the likely destination.
/// They are synchronous and must answer from work already done (for example conversions prepared
/// while the Fits card was computed).
@MainActor protocol FlixDragIntercepting: AnyObject {
    /// Files to carry instead of the originals, such as a PDF made from an image for a portal that
    /// takes PDFs only. Nil carries the originals.
    func plan(for items: [FlixItem], context: FlixFrontmostContext?, fits: FlixFitsResult?) -> FlixDragPlan?
    /// A question to ask before the drag starts. Phase A already asks for annotated sensitive items
    /// and older versions; a provider can add its own or return nil to defer to those.
    func confirmation(for items: [FlixItem], context: FlixFrontmostContext?) -> FlixDropConfirmation?
}

/// The providers phase B installs. Every slot is optional; nil keeps that surface hidden.
@MainActor struct FlixIntelligenceProviders {
    var fits: (any FlixFitsProviding)?
    var search: (any FlixSearchProviding)?
    var threads: (any FlixThreadProviding)?
    var annotations: (any FlixAnnotationProviding)?
    var morning: (any FlixMorningProviding)?
    var similarity: (any FlixSimilarityProviding)?
    var smartFilters: (any FlixSmartFilterGenerating)?
    var tidy: (any FlixTidyProviding)?
    var robi: (any FlixRobiProviding)?
    var dragMemory: (any FlixDragMemoryProviding)?
    var drag: (any FlixDragIntercepting)?

    init() {}
}
