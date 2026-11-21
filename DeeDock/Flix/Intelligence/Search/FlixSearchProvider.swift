import Foundation

/// Search in plain words ("contract Mike sent last week", "Rechnungen über 1.000 €").
///
/// Apple Intelligence reads the sentence into fields (`FlixQueryModel`), backed by the English and
/// German rules (`FlixQueryParser`); the fields become editable tokens (`FlixQueryTokens`). Items
/// match the tokens' rules, and the topic matches names, captions, folders, and, with Lookout, file
/// contents by meaning (`FlixSearchMatcher`). Lookout's matches are kept in the topic cache, so the
/// list stays right when a token is removed and the rules are evaluated directly.
///
/// The panel debounces typing (420 ms); `FlixIntelligence` cancels a search when the next one
/// starts, which ends its model call and its Lookout query. A sentence that is only one word and
/// can't be searched by meaning is left to the plain name search.
@MainActor
final class FlixSearchProvider: FlixSearchProviding {
    private let services: FlixSmartServices

    init(services: FlixSmartServices) {
        self.services = services
    }

    var examples: [String] {
        [String(localized: .flixSearchExampleSent), String(localized: .flixSearchExampleScreenshot),
         String(localized: .flixSearchExamplePhotos), String(localized: .flixSearchExampleInvoices)]
    }

    func understand(_ text: String, items: [FlixItem], now: Date) async
        -> (tokens: [FlixQueryToken], matches: [FlixItem.ID: FlixMatchKind]?)? {
        let understanding = await FlixQueryModel.understand(text)
        guard !Task.isCancelled, !understanding.isEmpty else { return nil }
        let topicOnly = understanding == FlixQueryUnderstanding(topic: understanding.topic)
        if topicOnly, FlixWords.words(understanding.topic ?? "").count < 2, !services.semantic.isAvailable { return nil }

        let tokens = FlixQueryTokens.tokens(for: understanding)
        var context = FlixSearchMatcher.Context()
        for item in items {
            guard let path = item.path, let record = services.analyses[path] else { continue }
            if let caption = record.caption { context.captions[item.id] = caption }
            if let total = record.total { context.totals[item.id] = total }
        }
        if let topic = understanding.topic, let found = await services.semantic.contentMatches(topic) {
            guard !Task.isCancelled else { return nil }
            context.meaningPaths = Set(found.keys)
            services.topics.store(topic: topic, paths: Set(found.keys))
        }
        let rules = tokens.map(\.rule)
        var matches = FlixSearchMatcher.matches(rules, in: items, context: context, now: now)
        // Nothing has every word: widen to any distinctive word in the name, so a name the person
        // half remembers still turns up.
        if matches.isEmpty, let topic = understanding.topic, FlixWords.words(topic).count > 1 {
            let words = FlixWords.distinctive(topic)
            let widened = rules.filter { if case .about = $0 { false } else { true } }
            let candidates = items.filter { !FlixWords.distinctive($0.name).isDisjoint(with: words) }
            matches = FlixSearchMatcher.matches(widened, in: candidates, context: context, now: now)
        }
        return (tokens, matches)
    }
}
