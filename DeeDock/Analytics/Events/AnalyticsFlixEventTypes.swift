import Foundation

// Flix Files' analytics vocabulary. Every value is a closed token, a Bool, an exact number, or an
// `AnalyticsFileType`; nothing here can hold a file name, a path, a URL or host, a query, an AI
// prompt or answer, an app name, a bundle ID, or a window title. App and website identity is
// reduced on the Mac to `FlixAppCategory` and `AnalyticsFlixPageKind`. `docs/ANALYTICS.md`
// (`### Flix Files`) lists every event and must change together with this file.

/// The app in front, or a drop's destination app, as a category only (see `FlixAppCategory`).
extension FlixAppCategory: AnalyticsToken {}

/// How the panel was opened.
nonisolated enum AnalyticsFlixTrigger: String, AnalyticsToken {
    case tileClick = "tile_click", tileDrag = "tile_drag", shortcut, menuBar = "menu_bar", discovery
}

/// Where the panel sat.
nonisolated enum AnalyticsFlixPlacement: String, AnalyticsToken {
    case tile, pointer, menuBar = "menu_bar"
}

/// What kind of web page a link or a browser destination is. Never the host.
nonisolated enum AnalyticsFlixPageKind: String, AnalyticsToken {
    case uploadForm = "upload_form", webDocument = "web_document", webmail, otherPage = "other_page"
}

/// The part of the panel an item was acted on from.
nonisolated enum AnalyticsFlixSection: String, AnalyticsToken {
    case fits, stream, thread, search, favorites
    case smartFilter = "smart_filter", moreLikeThis = "more_like_this", morningCard = "morning_card"
    case flagged, activityFilter = "activity_filter", kindFilter = "kind_filter"
}

/// What last happened to an item.
nonisolated enum AnalyticsFlixItemEvent: String, AnalyticsToken {
    case opened, downloaded, new, saved, link, app
}

/// An item's kind: its file type (``AnalyticsFileType``, reduced to a system type) for files, else
/// `folder`, `app`, or `link`.
nonisolated struct AnalyticsFlixItemKind: Equatable, Sendable {
    nonisolated enum Other: String, AnalyticsToken { case folder, app, link }

    private enum Storage: Equatable, Sendable {
        case file(AnalyticsFileType)
        case other(Other)
    }

    private let storage: Storage

    init(file type: AnalyticsFileType) { storage = .file(type) }
    init(_ other: Other) { storage = .other(other) }

    static let folder = AnalyticsFlixItemKind(.folder)
    static let app = AnalyticsFlixItemKind(.app)
    static let link = AnalyticsFlixItemKind(.link)

    var value: AnalyticsValue {
        switch storage {
        case let .file(type): AnalyticsValue(type)
        case let .other(other): AnalyticsValue(other)
        }
    }
}

/// How one panel visit ended. Actions win over the way it closed: a visit that dragged something out
/// is `dragged_out` however the panel went away.
nonisolated enum AnalyticsFlixOutcome: String, AnalyticsToken {
    case draggedOut = "dragged_out", opened, revealed, copied, robi, quickLookOnly = "quick_look_only"
    case nothing, escape, clickedAway = "clicked_away", shortcutToggle = "shortcut_toggle"
}

/// Which reader produced the text "Fits this window" matched against.
nonisolated enum AnalyticsFlixReader: String, AnalyticsToken {
    case accessibility, vision, appleIntelligenceImage = "apple_intelligence_image", none, disabled
    case noPermission = "no_permission"
}

/// Where a drag out started.
nonisolated enum AnalyticsFlixDropSource: String, AnalyticsToken {
    case row, threadCard = "thread_card", tile, fits
}

/// Where a drag out landed, as far as DOKK can tell: DOKK's own targets exactly, other apps by the
/// category of the window under the drop point.
nonisolated enum AnalyticsFlixDropTarget: String, AnalyticsToken {
    case browserUpload = "browser_upload", page, mailCompose = "mail_compose", chat, finder
    case dockApp = "dock_app", favoriteFolder = "favorite_folder", favoriteApp = "favorite_app", shelf, trash
    case otherApp = "other_app"
}

/// The question asked before a drag.
nonisolated enum AnalyticsFlixWarning: String, AnalyticsToken {
    case none, sensitive, olderVersion = "older_version"
}

/// The answer to that question.
nonisolated enum AnalyticsFlixWarningResolution: String, AnalyticsToken {
    case sendAnyway = "send_anyway", useNewest = "use_newest", cancel
}

/// One understood piece of a plain-words search, by type only.
nonisolated enum AnalyticsFlixQueryTokenType: String, AnalyticsToken {
    case event, kind, time, amount, about, place
}

/// What understood a search sentence.
nonisolated enum AnalyticsFlixParser: String, AnalyticsToken {
    case appleIntelligence = "apple_intelligence", rules
}

/// How a search, or More like this, ended.
nonisolated enum AnalyticsFlixResultOutcome: String, AnalyticsToken {
    case opened, dragged, none
}

/// How the chosen search result matched.
nonisolated enum AnalyticsFlixMatch: String, AnalyticsToken {
    case name, meaning
}

/// An inline suggestion's kind.
nonisolated enum AnalyticsFlixSuggestionType: String, AnalyticsToken {
    case move, rename
}

nonisolated enum AnalyticsFlixSuggestionAction: String, AnalyticsToken {
    case accepted, undone
}

/// How a Smart Filter came to be.
nonisolated enum AnalyticsFlixFilterSource: String, AnalyticsToken {
    case sentence, tip, manual
}

/// A Smart Filter rule, by kind only.
nonisolated enum AnalyticsFlixRuleKind: String, AnalyticsToken {
    case location, kind, tag, name, meaning, event
}

/// What wrote a Smart Filter from a sentence.
nonisolated enum AnalyticsFlixGenerator: String, AnalyticsToken {
    case appleIntelligence = "apple_intelligence", rules
}

nonisolated enum AnalyticsFlixThreadAction: String, AnalyticsToken {
    case filter, openAll = "open_all", dragCard = "drag_card", robi
}

/// What named a Thread.
nonisolated enum AnalyticsFlixThreadNamer: String, AnalyticsToken {
    case appleIntelligence = "apple_intelligence", folder
}

nonisolated enum AnalyticsFlixMorningAction: String, AnalyticsToken {
    case reopen, thread, dismiss, ignored
}

/// Which question was asked: one of the three suggestions, by position, or a typed one. Never the text.
nonisolated enum AnalyticsFlixRobiQuestion: String, AnalyticsToken {
    case suggested1 = "suggested_1", suggested2 = "suggested_2", suggested3 = "suggested_3", typed

    /// The token for a suggestion at a 0-based position, or `typed` for anything else.
    init(suggestionIndex: Int?) {
        switch suggestionIndex {
        case 0: self = .suggested1
        case 1: self = .suggested2
        case 2: self = .suggested3
        default: self = .typed
        }
    }
}

nonisolated enum AnalyticsFlixRobiResult: String, AnalyticsToken {
    case answered, failed, cancelled, noKey = "no_key"
}

/// Why a link item was recorded.
nonisolated enum AnalyticsFlixLinkTrigger: String, AnalyticsToken {
    case downloadSource = "download_source", sentTo = "sent_to", webDocument = "web_document"
    case savedDrag = "saved_drag", savedButton = "saved_button", read
}

nonisolated enum AnalyticsFlixAccessResult: String, AnalyticsToken {
    case granted, denied
}

/// A watched folder, by well-known place only.
nonisolated enum AnalyticsFlixFolder: String, AnalyticsToken {
    case desktop, documents, downloads, icloudDrive = "icloud_drive", other
}

nonisolated enum AnalyticsFlixShortcutResult: String, AnalyticsToken {
    case registered, unavailable
}

nonisolated enum AnalyticsFlixTip: String, AnalyticsToken {
    case smartFilter = "smart_filter", discovery
}

nonisolated enum AnalyticsFlixTipAction: String, AnalyticsToken {
    case accepted, dismissed
}

/// A key combination as a token such as `ctrl_opt_cmd_f`: the modifiers in the order ctrl, opt,
/// shift, cmd, then the key's name from a closed list (letters, digits, `space`, `f1`…`f20`,
/// arrows, and named punctuation and editing keys; anything else is `other`).
///
/// The token is built from a key code and modifier bits, never from typed text, and
/// ``init(rawValue:)`` accepts only strings that grammar produces, so no other text can pass.
nonisolated struct AnalyticsShortcutCombo: AnalyticsToken, Equatable, Hashable {
    static let modifierNames = ["ctrl", "opt", "shift", "cmd"]

    let rawValue: String

    /// Accepts only a token this type would build.
    init?(rawValue: String) {
        var parts = rawValue.split(separator: "_").map(String.init)
        guard let key = parts.popLast(), Self.keyNames.contains(key) else { return nil }
        var order = Self.modifierNames[...]
        for part in parts {
            guard let index = order.firstIndex(of: part) else { return nil }
            order = order[(index + 1)...]
        }
        self.rawValue = rawValue
    }

    /// - Parameters:
    ///   - keyName: One of ``keyNames``; anything else becomes `other`.
    ///   - control, option, shift, command: The modifiers held.
    init(keyName: String, control: Bool, option: Bool, shift: Bool, command: Bool) {
        let key = Self.keyNames.contains(keyName) ? keyName : "other"
        let modifiers = zip(Self.modifierNames, [control, option, shift, command]).filter(\.1).map(\.0)
        rawValue = (modifiers + [key]).joined(separator: "_")
    }

    /// Every key name a token can end with.
    static let keyNames: Set<String> = {
        var names = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        names.formUnion((1...20).map { "f\($0)" })
        names.formUnion(["space", "left", "right", "up", "down", "return", "enter", "tab", "delete", "fwddelete",
                         "escape", "home", "end", "pageup", "pagedown", "minus", "equal", "lbracket", "rbracket",
                         "semicolon", "quote", "comma", "period", "slash", "backslash", "grave", "other"])
        return names
    }()
}

// MARK: - Payloads

/// Everything `flix_session_ended` reports about one panel visit.
nonisolated struct AnalyticsFlixSession: Equatable, Sendable {
    /// The first thing done to an item in the visit.
    nonisolated struct FirstAction: Equatable, Sendable {
        var section: AnalyticsFlixSection
        /// 1-based within its section; nil where a section has no order (a thread card).
        var rank: Int?
        var itemKind: AnalyticsFlixItemKind?
        var itemEvent: AnalyticsFlixItemEvent?
        var itemAgeMinutes: Int?
    }

    var trigger: AnalyticsFlixTrigger
    var placement: AnalyticsFlixPlacement
    var displayBuiltin: Bool
    var keyboardOnly: Bool
    /// 0–23 on the Mac's clock.
    var localHour: Int
    /// ISO weekday, 1 = Monday … 7 = Sunday.
    var weekday: Int
    var durationMs: Int
    var timeToFirstActionMs: Int?
    var frontCategory: FlixAppCategory
    var unseenAtOpen: Int
    var listSizeAtOpen: Int
    var outcome: AnalyticsFlixOutcome
    var drags = 0
    var opens = 0
    var copies = 0
    var quickLooks = 0
    var flags = 0
    var favorites = 0
    var removes = 0
    var trashes = 0
    var firstAction: FirstAction?
    var filterChanges = 0
    var sidebarAreasUsed = 0
    var maxScrolledRows = 0
    var searchUsed = false
    var fitsShown = 0
    var fitsReader: AnalyticsFlixReader?
    var fitsReadyMs: Int?
    var fitsAccepted = false
    var fitsRank: Int?
    var morningCardShown = false
    var pinned = false

    var properties: AnalyticsProperties {
        ["trigger": .init(trigger), "placement": .init(placement), "display_builtin": .init(displayBuiltin),
         "keyboard_only": .init(keyboardOnly), "local_hour": .init(localHour), "weekday": .init(weekday),
         "duration_ms": .init(durationMs), "time_to_first_action_ms": timeToFirstActionMs.map(AnalyticsValue.init),
         "front_category": .init(frontCategory), "unseen_at_open": .init(unseenAtOpen),
         "list_size_at_open": .init(listSizeAtOpen), "outcome": .init(outcome),
         "drags": .init(drags), "opens": .init(opens), "copies": .init(copies), "quick_looks": .init(quickLooks),
         "flags": .init(flags), "favorites": .init(favorites), "removes": .init(removes), "trashes": .init(trashes),
         "first_action_section": firstAction.map { AnalyticsValue($0.section) },
         "first_action_rank": firstAction?.rank.map(AnalyticsValue.init),
         "first_action_item_kind": firstAction?.itemKind?.value,
         "first_action_item_event": firstAction?.itemEvent.map(AnalyticsValue.init),
         "first_action_item_age_minutes": firstAction?.itemAgeMinutes.map(AnalyticsValue.init),
         "filter_changes": .init(filterChanges), "sidebar_areas_used": .init(sidebarAreasUsed),
         "max_scrolled_rows": .init(maxScrolledRows), "search_used": .init(searchUsed),
         "fits_shown": .init(fitsShown), "fits_reader": fitsReader.map(AnalyticsValue.init),
         "fits_ready_ms": fitsReadyMs.map(AnalyticsValue.init), "fits_accepted": .init(fitsAccepted),
         "fits_rank": fitsRank.map(AnalyticsValue.init), "morning_card_shown": .init(morningCardShown),
         "pinned": .init(pinned)]
    }
}

/// `flix_drop`: a drag out that completed, or one the person cancelled at a warning.
nonisolated struct AnalyticsFlixDrop: Equatable, Sendable {
    var source: AnalyticsFlixDropSource
    var section: AnalyticsFlixSection?
    var rank: Int?
    var itemCount: Int
    /// Deduplicated, in order.
    var itemKinds: [AnalyticsFlixItemKind]
    var containsFolder: Bool
    var containsLink: Bool
    /// Nil for a drag cancelled at a warning.
    var target: AnalyticsFlixDropTarget?
    var targetCategory: FlixAppCategory?
    /// Only for a browser destination.
    var pageKind: AnalyticsFlixPageKind?
    var converted = false
    var convertedFrom: AnalyticsFileType?
    var convertedTo: AnalyticsFileType?
    var convertMs: Int?
    var warning: AnalyticsFlixWarning = .none
    var warningResolution: AnalyticsFlixWarningResolution?
    var panelPinned: Bool
    var predicted: Bool

    var properties: AnalyticsProperties {
        ["source": .init(source), "section": section.map(AnalyticsValue.init), "rank": rank.map(AnalyticsValue.init),
         "item_count": .init(itemCount), "item_kinds": .list(itemKinds.map(\.value)),
         "contains_folder": .init(containsFolder), "contains_link": .init(containsLink),
         "target": target.map(AnalyticsValue.init), "target_category": targetCategory.map(AnalyticsValue.init),
         "page_kind": pageKind.map(AnalyticsValue.init), "converted": .init(converted),
         "converted_from": convertedFrom.map(AnalyticsValue.init), "converted_to": convertedTo.map(AnalyticsValue.init),
         "convert_ms": convertMs.map(AnalyticsValue.init), "warning": .init(warning),
         "warning_resolution": warningResolution.map(AnalyticsValue.init), "panel_pinned": .init(panelPinned),
         "predicted": .init(predicted)]
    }
}

/// `flix_search_ended`. Counts and token types only, never the sentence.
nonisolated struct AnalyticsFlixSearch: Equatable, Sendable {
    var queryWordCount: Int
    var tokenCount: Int
    var tokenTypes: [AnalyticsFlixQueryTokenType]
    var tokensRemoved: [AnalyticsFlixQueryTokenType]
    /// Nil when the sentence was matched by name only (no provider, or one word).
    var parser: AnalyticsFlixParser?
    var parseMs: Int?
    var resultCount: Int
    var byMeaningCount: Int
    var lookoutAvailable: Bool
    var outcome: AnalyticsFlixResultOutcome
    var chosenRank: Int?
    var chosenMatch: AnalyticsFlixMatch?

    var properties: AnalyticsProperties {
        ["query_word_count": .init(queryWordCount), "token_count": .init(tokenCount),
         "token_types": .list(tokenTypes.map(AnalyticsValue.init)),
         "tokens_removed": .list(tokensRemoved.map(AnalyticsValue.init)),
         "parser": parser.map(AnalyticsValue.init), "parse_ms": parseMs.map(AnalyticsValue.init),
         "result_count": .init(resultCount), "by_meaning_count": .init(byMeaningCount),
         "lookout_available": .init(lookoutAvailable), "outcome": .init(outcome),
         "chosen_rank": chosenRank.map(AnalyticsValue.init), "chosen_match": chosenMatch.map(AnalyticsValue.init)]
    }
}

/// `flix_fits_computed`: one reading of the window in front. Word counts, never the words.
nonisolated struct AnalyticsFlixFits: Equatable, Sendable {
    var reader: AnalyticsFlixReader
    var stepsTried: Int
    var axWords: Int
    var ocrWords: Int
    var intentItems: Int
    var hasTypeLimit: Bool
    var hasSizeLimit: Bool
    var matches: Int
    var readyMs: Int
    var frontCategory: FlixAppCategory
    /// Only for a browser window.
    var pageKind: AnalyticsFlixPageKind?

    var properties: AnalyticsProperties {
        ["reader": .init(reader), "steps_tried": .init(stepsTried), "ax_words": .init(axWords),
         "ocr_words": .init(ocrWords), "intent_items": .init(intentItems), "has_type_limit": .init(hasTypeLimit),
         "has_size_limit": .init(hasSizeLimit), "matches": .init(matches), "ready_ms": .init(readyMs),
         "front_category": .init(frontCategory), "page_kind": pageKind.map(AnalyticsValue.init)]
    }
}

/// `flix_tidy`: the Tidy sheet was applied or dismissed.
nonisolated struct AnalyticsFlixTidy: Equatable, Sendable {
    var shownMoves: Int
    var shownRenames: Int
    var appliedMoves = 0
    var appliedRenames = 0
    var unchecked = 0
    var undone = false

    var properties: AnalyticsProperties {
        ["shown_moves": .init(shownMoves), "shown_renames": .init(shownRenames), "applied_moves": .init(appliedMoves),
         "applied_renames": .init(appliedRenames), "unchecked": .init(unchecked), "undone": .init(undone)]
    }
}

/// `flix_robi_asked`: metadata of one Ask Robi request. Never the question or the answer.
nonisolated struct AnalyticsFlixRobi: Equatable, Sendable {
    var question: AnalyticsFlixRobiQuestion
    var selectionCount: Int
    var itemKinds: [AnalyticsFlixItemKind]
    var latencyMs: Int
    var result: AnalyticsFlixRobiResult

    var properties: AnalyticsProperties {
        ["question": .init(question), "selection_count": .init(selectionCount),
         "item_kinds": .list(itemKinds.map(\.value)), "latency_ms": .init(latencyMs), "result": .init(result)]
    }
}

// MARK: - Counters

/// Flix Files' counters in `usage_summary`. `_sum`/`_count`/`_max` triples give averages and the
/// slowest case of a timing without one event per occurrence.
nonisolated enum AnalyticsFlixCounter: String, Sendable {
    case itemsOpened = "flix_items_opened", itemsDownloaded = "flix_items_downloaded", itemsNew = "flix_items_new"
    case itemsSaved = "flix_items_saved", itemsApp = "flix_items_app"
    case linksRecorded = "flix_links_recorded", linksPrivateSkipped = "flix_links_private_skipped"
    case linksExcludedSkipped = "flix_links_excluded_skipped", linkTokensStripped = "flix_link_tokens_stripped"
    case noiseFiltered = "flix_noise_filtered", captionsGenerated = "flix_captions_generated"
    case aiCacheHits = "flix_ai_cache_hits", aiFailures = "flix_ai_failures"
    case fitsPillShown = "flix_fits_pill_shown", tileClickedWithPill = "flix_tile_clicked_with_pill"
    case openLatencySum = "flix_open_latency_ms_sum", openLatencyCount = "flix_open_latency_count"
    case openLatencyMax = "flix_open_latency_ms_max"
    case windowReadSum = "flix_window_read_ms_sum", windowReadCount = "flix_window_read_count"
    case windowReadMax = "flix_window_read_ms_max"
}

extension Analytics {
    /// Adds one Flix Files counter.
    static func count(_ counter: AnalyticsFlixCounter, by amount: Int = 1) {
        count(.flix(counter), by: amount)
    }

    /// Records one timing as a `_sum`, `_count`, and `_max` triple.
    static func countTiming(sum: AnalyticsFlixCounter, count countKey: AnalyticsFlixCounter,
                            max: AnalyticsFlixCounter, milliseconds: Int) {
        let value = Swift.max(0, milliseconds)
        count(.flix(sum), by: value)
        count(.flix(countKey))
        countMaximum(.flix(max), value)
    }
}
