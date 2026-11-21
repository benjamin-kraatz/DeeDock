import Foundation

/// Turns an understood sentence into a Smart Filter and describes its rules for the proposal card.
///
/// When the topic names a folder the person files things in ("Oak & Ash"), the filter matches
/// anything in that folder **or** about the topic by meaning; otherwise every rule must hold. The
/// name is the model's, or the folder or topic, capitalized.
@MainActor
enum FlixSmartFilterBuilder {
    /// The folder names under which history items sit, for matching a topic to a folder.
    static func folderNames(in items: [FlixItem]) -> Set<String> {
        Set(items.compactMap { item in
            item.path.map { (($0 as NSString).deletingLastPathComponent as NSString).lastPathComponent }
        }.filter { !$0.isEmpty })
    }

    /// The filter for `understanding`, or nil when it has no rule.
    ///
    /// - Parameters:
    ///   - name: The model's name, when it gave one.
    ///   - emoji: The model's emoji, when it gave one.
    ///   - folders: Folder names from ``folderNames(in:)``.
    static func filter(for understanding: FlixQueryUnderstanding, sentence: String, name: String?, emoji: String?,
                       folders: Set<String>) -> FlixSmartFilter? {
        var rules: [FlixSmartFilterRule] = []
        if let activity = understanding.activity { rules.append(.activity(activity)) }
        rules += understanding.kinds.map(FlixSmartFilterRule.kind)
        rules += understanding.extensions.map(FlixSmartFilterRule.fileExtension)
        if let days = understanding.days { rules.append(.withinDays(days)) }
        if let amount = understanding.minimumAmount { rules.append(.amountOver(amount)) }
        if let site = understanding.site { rules.append(.sourceContains(site)) }
        var match = FlixSmartFilter.Match.all
        var folder = understanding.folder
        if let topic = understanding.topic, !topic.isEmpty {
            let topicWords = Set(FlixWords.words(topic))
            let related = { (name: String) -> Bool in
                let words = Set(FlixWords.words(name)).subtracting(FlixWords.generic)
                return !words.isEmpty && (words.isSubset(of: topicWords) || topicWords.isSubset(of: words))
            }
            if folder == nil {
                folder = folders.filter(related).max { FlixWords.words($0).count < FlixWords.words($1).count }
            }
            if let folder, rules.isEmpty, related(folder) {
                // One thing named: the folder for it, or anything about it.
                rules = [.locationContains(folder), .about(topic)]
                match = .any
            } else {
                if let folder { rules.append(.locationContains(folder)) }
                rules.append(.about(topic))
            }
        } else if let folder {
            rules.append(.locationContains(folder))
        }
        guard !rules.isEmpty else { return nil }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? folder ?? understanding.topic.map(capitalizedFirst) ?? capitalizedFirst(sentence)
        return FlixSmartFilter(name: String(title.prefix(40)), emoji: emoji ?? fallbackEmoji(sentence, understanding),
                               match: match, rules: rules)
    }

    /// One line per rule, Markdown, joined by "and" or "or": "Location contains `Oak & Ash`",
    /// "or about `Oak & Ash` by meaning".
    static func descriptions(for filter: FlixSmartFilter, byMeaning: Bool) -> [String] {
        filter.rules.enumerated().map { index, rule in
            let text = describe(rule, byMeaning: byMeaning)
            guard index > 0 else { return capitalizedFirst(text) }
            return filter.match == .any ? String(localized: .flixRuleJoinOr(text)) : String(localized: .flixRuleJoinAnd(text))
        }
    }

    static func describe(_ rule: FlixSmartFilterRule, byMeaning: Bool) -> String {
        switch rule {
        case .nameContains(let text): String(localized: .flixRuleTextName(text))
        case .locationContains(let text): String(localized: .flixRuleTextLocation(text))
        case .kind(let kind): String(localized: .flixRuleTextKind(FlixQueryTokens.kindLabel(kind)))
        case .activity(let activity): String(localized: .flixRuleTextActivity(activityTitle(activity)))
        case .sourceContains(let text): String(localized: .flixRuleTextSource(text))
        case .fileExtension(let ext): String(localized: .flixRuleTextExtension(ext.uppercased()))
        case .withinDays(let days): String(localized: .flixRuleTextDays(days))
        case .flagged: String(localized: .flixRuleTextFlagged)
        case .about(let topic): byMeaning ? String(localized: .flixRuleTextAbout(topic)) : String(localized: .flixRuleTextAboutWords(topic))
        case .amountOver(let amount):
            String(localized: .flixRuleTextAmount(amount.formatted(.currency(code: "EUR").precision(.fractionLength(0)))))
        }
    }

    private static func activityTitle(_ activity: FlixActivity) -> String {
        switch activity {
        case .opened: String(localized: FlixFilter.Activity.opened.title)
        case .downloaded: String(localized: FlixFilter.Activity.downloaded.title)
        case .created: String(localized: FlixFilter.Activity.created.title)
        case .saved: String(localized: FlixFilter.Activity.saved.title)
        case .link: String(localized: .flixTokenLinks)
        case .kept: String(localized: .flixRuleTextKept)
        }
    }

    static func fallbackEmoji(_ sentence: String, _ understanding: FlixQueryUnderstanding) -> String {
        let words = Set(FlixWords.words(sentence).map(FlixWords.stem))
        let map: [(Set<String>, String)] = [
            (["tax", "steuer", "invoice", "rechnung", "receipt", "quittung", "bill", "finance", "finanzen", "money", "geld"], "🧾"),
            (["trip", "travel", "reise", "urlaub", "holiday", "vacation", "ferien"], "🧳"),
            (["code", "build", "dev", "xcode", "swift", "bug", "fehler"], "🛠️"),
            (["contract", "vertrag", "agreement", "legal"], "✍️"),
            (["client", "kunde", "kunden", "project", "projekt"], "💼"),
        ]
        if let hit = map.first(where: { !$0.0.isDisjoint(with: words) }) { return hit.1 }
        if understanding.kinds.contains(.image) || understanding.kinds.contains(.screenshot) { return "📷" }
        return "✨"
    }

    static func capitalizedFirst(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
