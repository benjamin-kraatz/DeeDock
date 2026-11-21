import Foundation

/// Matches understood search tokens against the history and says how each item matched.
///
/// Every rule but `.about` must hold (`FlixSmartFilterRule.matches`, with totals answering
/// `.amountOver`). An `.about` topic then matches by name when every word is in the item's name;
/// "by meaning" when the words are in its caption, folders, or source, or when Lookout matched its
/// content. Pure, so it is tested without Lookout.
nonisolated enum FlixSearchMatcher {
    struct Context: Sendable {
        /// Captions from the analysis cache.
        var captions: [FlixItem.ID: String] = [:]
        /// Totals from the analysis cache, for `.amountOver`.
        var totals: [FlixItem.ID: Double] = [:]
        /// Paths Lookout matched for the topic; nil without Lookout.
        var meaningPaths: Set<String>?
    }

    static func matches(_ rules: [FlixSmartFilterRule], in items: [FlixItem], context: Context,
                        now: Date) -> [FlixItem.ID: FlixMatchKind] {
        let topics = rules.compactMap { rule -> [String]? in
            if case .about(let topic) = rule { FlixWords.words(topic) } else { nil }
        }
        let structural = rules.filter { if case .about = $0 { false } else { true } }
        var result: [FlixItem.ID: FlixMatchKind] = [:]
        for item in items {
            let semantic: (String, FlixItem) -> Bool? = { topic, item in
                FlixSmartFilterRule.amount(inTopic: topic).map { amount in (context.totals[item.id] ?? 0) > amount }
            }
            guard structural.allSatisfy({ $0.matches(item, now: now, semantic: semantic) }) else { continue }
            var kind = FlixMatchKind.name
            var matched = true
            for words in topics {
                guard let found = match(words, item: item, context: context) else { matched = false; break }
                if found == .meaning { kind = .meaning }
            }
            if matched { result[item.id] = kind }
        }
        return result
    }

    /// How `words` match `item`, or nil when they don't.
    static func match(_ words: [String], item: FlixItem, context: Context) -> FlixMatchKind? {
        guard !words.isEmpty else { return .name }
        if FlixWords.containsAll(words, in: item.name) { return .name }
        let around = [context.captions[item.id] ?? "", item.path.map { ($0 as NSString).deletingLastPathComponent } ?? "",
                      item.sourceHost ?? "", item.link?.title ?? ""].joined(separator: " ")
        if FlixWords.containsAll(words, in: around) { return .meaning }
        if let path = item.path, context.meaningPaths?.contains(path) == true { return .meaning }
        return nil
    }
}
