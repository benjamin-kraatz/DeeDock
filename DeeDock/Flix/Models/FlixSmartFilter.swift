import Foundation

/// A saved filter in the sidebar's Smart Filters section. New items join by themselves because the
/// rules are evaluated against the live history every time the list is built.
///
/// Rules are plain data so a filter made from a sentence (phase B2) and one built by hand persist
/// the same way. ``FlixSmartFilterRule/about(_:)`` is the one semantic rule: phase B2's provider
/// answers it by meaning; without a provider it falls back to matching the words.
nonisolated struct FlixSmartFilter: Codable, Identifiable, Hashable, Sendable {
    nonisolated enum Match: String, Codable, Sendable { case all, any }

    var id: UUID
    var name: String
    /// One emoji drawn as the sidebar glyph.
    var emoji: String
    var match: Match
    var rules: [FlixSmartFilterRule]
    /// How the filter was made, for analytics when it is added or deleted. Nil in filters saved
    /// before it was recorded, which count as made by hand.
    var origin: FlixSmartFilterOrigin?

    init(id: UUID = UUID(), name: String, emoji: String = "✨", match: Match = .all,
         rules: [FlixSmartFilterRule], origin: FlixSmartFilterOrigin? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.match = match
        self.rules = rules
        self.origin = origin
    }

    /// Whether `item` belongs in this filter.
    ///
    /// - Parameters:
    ///   - now: The reference time for ``FlixSmartFilterRule/withinDays(_:)``.
    ///   - semantic: Answers an ``FlixSmartFilterRule/about(_:)`` rule by meaning, or returns nil to
    ///     fall back to word matching. Must be cheap: it runs for every item on every list build, so
    ///     providers answer from a cache they filled in the background.
    func matches(_ item: FlixItem, now: Date = .now,
                 semantic: (String, FlixItem) -> Bool? = { _, _ in nil }) -> Bool {
        guard !rules.isEmpty else { return false }
        switch match {
        case .all: return rules.allSatisfy { $0.matches(item, now: now, semantic: semantic) }
        case .any: return rules.contains { $0.matches(item, now: now, semantic: semantic) }
        }
    }
}

/// How a Smart Filter was made.
nonisolated enum FlixSmartFilterOrigin: String, Codable, Sendable {
    /// Written from a sentence in the New Smart Filter sheet.
    case sentence
    /// The sidebar's ✦ tip.
    case tip
    /// Built rule by rule.
    case manual
}

/// One condition of a Smart Filter. Persisted with Swift's synthesized enum coding; add cases, never
/// rename them.
nonisolated enum FlixSmartFilterRule: Codable, Hashable, Sendable {
    /// The name contains the text, ignoring case and diacritics.
    case nameContains(String)
    /// A folder on the item's path contains the text ("Oak & Ash").
    case locationContains(String)
    /// The item is of this kind. `.image` includes screenshots.
    case kind(FlixItemKind)
    /// The latest activity is this one.
    case activity(FlixActivity)
    /// The download page's host contains the text.
    case sourceContains(String)
    /// The file name extension, without the dot, ignoring case.
    case fileExtension(String)
    /// The latest activity is at most this many days old.
    case withinDays(Int)
    /// The item is flagged.
    case flagged
    /// The item is about this topic. Answered by meaning when phase B2's provider can, otherwise by
    /// matching every word against the name and location.
    case about(String)
    /// The file's total (a key fact phase B2 read from it) is above this amount. Answered through
    /// the same cached lookup as `.about`, asked with ``amountTopic(_:)``; without an answer nothing
    /// matches.
    case amountOver(Double)

    /// The lookup topic an `.amountOver` rule asks the semantic closure. Never shown.
    static func amountTopic(_ amount: Double) -> String { amountTopicPrefix + String(amount) }

    /// The amount in a topic made by ``amountTopic(_:)``, or nil for an ordinary topic.
    static func amount(inTopic topic: String) -> Double? {
        topic.hasPrefix(amountTopicPrefix) ? Double(topic.dropFirst(amountTopicPrefix.count)) : nil
    }

    private static let amountTopicPrefix = "\u{1}amount>"

    func matches(_ item: FlixItem, now: Date, semantic: (String, FlixItem) -> Bool?) -> Bool {
        switch self {
        case .nameContains(let text):
            return !text.isEmpty && item.name.localizedStandardContains(text)
        case .locationContains(let text):
            guard !text.isEmpty, let path = item.path else { return false }
            let folders = (path as NSString).deletingLastPathComponent
            return folders.localizedStandardContains(text)
        case .kind(let kind):
            return item.kind == kind || (kind == .image && item.kind == .screenshot)
        case .activity(let activity):
            return item.activity == activity
        case .sourceContains(let text):
            guard !text.isEmpty else { return false }
            return (item.sourceHost ?? item.link?.host)?.localizedStandardContains(text) == true
        case .fileExtension(let ext):
            let wanted = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            return !wanted.isEmpty && item.fileExtension.lowercased() == wanted
        case .withinDays(let days):
            return now.timeIntervalSince(item.date) <= Double(max(0, days)) * 86_400
        case .flagged:
            return item.isFlagged
        case .about(let topic):
            if let answer = semantic(topic, item) { return answer }
            let words = topic.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
            guard !words.isEmpty else { return false }
            let haystack = [item.name, item.path ?? "", item.sourceHost ?? "", item.link?.title ?? ""]
                .joined(separator: " ")
            return words.allSatisfy { haystack.localizedStandardContains($0) }
        case .amountOver(let amount):
            return semantic(Self.amountTopic(amount), item) ?? false
        }
    }
}
