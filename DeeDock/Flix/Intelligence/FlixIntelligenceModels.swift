import Foundation

// The values phase B's providers hand to `FlixIntelligence`, and the UI draws. Plain data: views
// never call a provider, and nothing here knows which engine produced it.

/// One step of reading the window in front for "Fits this window".
nonisolated enum FlixReaderStep: String, CaseIterable, Sendable {
    /// The window's accessibility text (Robi's reader).
    case accessibility
    /// Vision text recognition on a capture of that one window.
    case vision
    /// Apple Intelligence looking at the window image.
    case appleIntelligence
}

/// Which readers were tried and which one produced the text, for the Fits card's
/// "~~Accessibility~~ → Vision" label.
nonisolated struct FlixReaderChain: Equatable, Sendable {
    /// In order. The last one is the reader in progress or the one that succeeded.
    var steps: [FlixReaderStep]
    /// True once the last step produced enough text.
    var succeeded: Bool

    init(steps: [FlixReaderStep] = [], succeeded: Bool = false) {
        self.steps = steps
        self.succeeded = succeeded
    }
}

/// What the window in front asks for, as Apple Intelligence interpreted it.
nonisolated struct FlixWindowIntent: Equatable, Sendable {
    /// Uniform type identifiers it accepts ("com.adobe.pdf"). Empty accepts anything.
    var acceptedTypes: [String] = []
    /// Largest file it takes, in bytes.
    var maximumBytes: Int64?
    /// Folders and apps would be refused.
    var filesOnly = false
}

/// One suggestion in the Fits section.
nonisolated struct FlixFit: Identifiable, Equatable, Sendable {
    var itemID: FlixItem.ID
    /// The window's own words this item answers, shown in quotes: "the signed contract".
    var phrase: String
    /// Set when drag memory knows you sent this kind of file to this window before.
    var memory: FlixDragReason?
    var id: FlixItem.ID { itemID }
}

/// The finished reading of one window.
nonisolated struct FlixFitsResult: Equatable, Sendable {
    /// The window, as the card names it: a host for a browser, otherwise the title or app name.
    var windowLabel: String
    var chain: FlixReaderChain
    var fits: [FlixFit]
    var intent: FlixWindowIntent?
}

/// The Fits section's state. Hidden draws nothing.
nonisolated enum FlixFitsState: Equatable, Sendable {
    case hidden
    /// Reading the window; the card shows shimmering rows and the chain so far.
    case reading(windowLabel: String, chain: FlixReaderChain)
    case ready(FlixFitsResult)
}

/// How a search result matched, for the "✦ by meaning" chip.
nonisolated enum FlixMatchKind: Equatable, Sendable {
    case name
    case meaning
}

/// One understood piece of a plain-words search ("↓ Downloaded", "Last 7 days", "about contract").
/// Removing a token narrows the search less. Each token is a Smart Filter rule, so a search can
/// be saved as a filter unchanged.
nonisolated struct FlixQueryToken: Identifiable, Equatable, Sendable {
    var id = UUID()
    /// Shown on the token.
    var label: String
    var rule: FlixSmartFilterRule
}

/// The search's state when a provider understands sentences. Without one, search matches names.
nonisolated enum FlixQueryState: Equatable, Sendable {
    case idle
    /// Shown as "✦ Understanding…" with shimmering rows.
    case understanding
    /// `matches` ranks items when the provider searched by meaning; nil means "apply the tokens' rules".
    case understood(tokens: [FlixQueryToken], matches: [FlixItem.ID: FlixMatchKind]?)
}

/// A group of related activity in the sidebar's ✦ Threads section, with its card.
nonisolated struct FlixThread: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var emoji: String
    /// One or two sentences for the thread card.
    var summary: String?
    var memberIDs: [FlixItem.ID]
    /// Shows "✦ named by Apple Intelligence" on the card.
    var namedByAppleIntelligence = false
}

/// A short fact chip on a row ("Due Dec 4", "€1,240").
nonisolated struct FlixFact: Hashable, Sendable {
    nonisolated enum Style: String, Sendable { case plain, due, signature, money }
    var text: String
    var style: Style = .plain
}

/// What phase B knows about one item. Every field is optional; the row shows what is there.
nonisolated struct FlixItemAnnotation: Equatable, Sendable {
    /// A one-line description replacing the event line ("Oak & Ash packaging quote, 3 options").
    var caption: String?
    /// A better file name, offered as "✦ Rename".
    var renameSuggestion: String?
    var facts: [FlixFact] = []
    /// A folder (absolute path) a download belongs in, offered as "✦ Move to …".
    var folderSuggestion: String?
    /// The item shows an ID, bank details, or a key: its preview blurs and a drop outside asks first.
    var isSensitive = false
    var sensitiveReason: String?
    /// Items sharing a group are versions of one document. Higher rank is newer.
    var versionGroup: String?
    var versionRank: Int?
    /// A learned noise verdict. Nil leaves it to `FlixNoiseRules`.
    var isNoise: Bool?

    init(caption: String? = nil, renameSuggestion: String? = nil, facts: [FlixFact] = [],
         folderSuggestion: String? = nil, isSensitive: Bool = false, sensitiveReason: String? = nil,
         versionGroup: String? = nil, versionRank: Int? = nil, isNoise: Bool? = nil) {
        self.caption = caption
        self.renameSuggestion = renameSuggestion
        self.facts = facts
        self.folderSuggestion = folderSuggestion
        self.isSensitive = isSensitive
        self.sensitiveReason = sensitiveReason
        self.versionGroup = versionGroup
        self.versionRank = versionRank
        self.isNoise = isNoise
    }
}

/// The morning "Where were you?" card.
nonisolated struct FlixMorningCard: Equatable, Sendable {
    nonisolated struct Action: Identifiable, Equatable, Sendable {
        nonisolated enum Target: Equatable, Sendable {
            case open([FlixItem.ID])
            case filter(FlixFilter)
        }
        var id = UUID()
        var label: String
        var target: Target
        var isPrimary = false
    }

    /// Markdown: `**bold**` names a thread or file.
    var message: String
    var actions: [Action]
}

/// "More like this" for one item.
nonisolated struct FlixMoreLikeThis: Equatable, Sendable {
    var sourceID: FlixItem.ID
    /// Nil while loading.
    var resultIDs: [FlixItem.ID]?
}

/// A Smart Filter made from a sentence, before it is added.
nonisolated struct FlixSmartFilterProposal: Equatable, Sendable {
    var filter: FlixSmartFilter
    /// Human-readable rules ("Location contains `Oak & Ash`"), Markdown.
    var ruleDescriptions: [String]
    /// Apple Intelligence wrote it; false: the rules alone.
    var generatedByModel = false
}

nonisolated enum FlixSmartFilterDraftState: Equatable, Sendable {
    case idle
    case generating
    case ready(FlixSmartFilterProposal)
    case failed
}

/// One row of the Tidy sheet: a rename, a move, or both.
nonisolated struct FlixTidySuggestion: Identifiable, Equatable, Sendable {
    var itemID: FlixItem.ID
    var rename: String?
    /// Destination folder, absolute path.
    var moveTo: String?
    var id: FlixItem.ID { itemID }
}

/// Ask Robi's answer.
nonisolated enum FlixRobiAnswerState: Equatable, Sendable {
    case idle
    /// Streaming; `text` grows.
    case answering(question: String, text: String)
    case answered(question: String, text: String)
    case failed(question: String, message: String)
}

/// Why drag memory suggests an item here ("you've sent PDFs here before").
nonisolated struct FlixDragReason: Equatable, Sendable {
    var text: String
}

/// The sidebar's inline tip card offering a Smart Filter.
nonisolated struct FlixFilterTip: Identifiable, Equatable, Sendable {
    var id: String
    var message: String
    var proposal: FlixSmartFilter
}

/// What a drag should carry instead of the original files, decided at drag start.
nonisolated struct FlixDragPlan: Equatable, Sendable {
    /// Files to write to the pasteboard in place of the item's own file, by item. They must exist
    /// when the plan is returned: browsers read file URLs, not promises.
    var substitutions: [FlixItem.ID: URL] = [:]
    /// The ghost label, such as "✦ Upload as PDF · 2 converted".
    var label: String?
    /// How long the slowest of the carried conversions took to make, in milliseconds.
    var convertMs: Int?
}

/// A question to ask before items leave for another app.
nonisolated enum FlixDropConfirmation: Equatable, Sendable {
    /// The item looks like an ID, bank details, or a key.
    case sensitive(itemID: FlixItem.ID, reason: String?, destination: String?)
    /// A newer version of the item exists.
    case newerVersion(itemID: FlixItem.ID, newerID: FlixItem.ID)
}

/// How each engine is doing, for Settings' "What powers it" rows. `FlixEngineMonitor` keeps
/// `FlixIntelligence.engines` current.
nonisolated struct FlixEngineStatus: Equatable, Sendable {
    nonisolated enum State: Equatable, Sendable {
        /// Not installed in this build (phase A) or not supported on this Mac.
        case unavailable
        case off
        /// Ready; `detail` is an optional count such as folders.
        case ready(detail: Int?)
        case needsSetup
    }
    var lookout: State = .unavailable
    var appleIntelligence: State = .unavailable
    var robi: State = .unavailable
    /// Robi's settings choose Apple Intelligence on this Mac, which needs no key; false: Claude.
    var robiOnDevice = false
}
