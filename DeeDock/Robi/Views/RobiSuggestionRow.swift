import SwiftUI

/// What hangs below the prompt bar: the built-in actions, and under them the questions Apple
/// Intelligence suggested for this context once they arrive.
///
/// The actions come in the order `RobiIntent.actions(canReplace:)` gives for this context. As
/// many lead as fit the row, and the rest wait in a More menu, together with any suggested
/// question too wide for its own row. The pills arrive one after another, each a few hundredths
/// of a second behind the last; Reduce Motion fades them in together.
struct RobiSuggestionRow: View {
    let model: RobiModel
    let actions: RobiActions
    /// Flips on appearance so each pill can animate in from its hidden state.
    @State private var shown = false

    private var questions: (shown: [String], overflow: [String]) {
        RobiPillFit.split(model.generatedSuggestions, available: RobiMetrics.cardWidth)
    }

    var body: some View {
        let intents = RobiIntent.actions(canReplace: model.canReplace)
        let questions = questions
        VStack(spacing: 6) {
            // Four leading actions in English and German; fewer only if a translation runs long.
            ViewThatFits(in: .horizontal) {
                RobiActionPills(model: model, actions: actions, intents: intents, leading: 4,
                                moreQuestions: questions.overflow, shown: shown)
                RobiActionPills(model: model, actions: actions, intents: intents, leading: 3,
                                moreQuestions: questions.overflow, shown: shown)
                RobiActionPills(model: model, actions: actions, intents: intents, leading: 2,
                                moreQuestions: questions.overflow, shown: shown)
            }
            if !questions.shown.isEmpty {
                RobiQuestionPills(model: model, actions: actions, questions: questions.shown)
            }
        }
        .frame(maxWidth: RobiMetrics.cardWidth)
        .onAppear { shown = true }
    }
}

/// The leading built-in actions as pills, then the More pill for the rest.
private struct RobiActionPills: View {
    let model: RobiModel
    let actions: RobiActions
    let intents: [RobiIntent]
    let leading: Int
    /// Suggested questions that did not fit their row; the More menu lists them last.
    let moreQuestions: [String]
    let shown: Bool

    /// Region and window text is still being read, so there is nothing to act on yet.
    private var waiting: Bool { model.isReadingContext && model.context?.text.isEmpty != false }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(intents.prefix(leading).enumerated()), id: \.element) { index, intent in
                Button { actions.suggest(intent) } label: {
                    Label { Text(intent.title) } icon: { Image(systemName: intent.symbol) }
                }
                .buttonStyle(RobiPillStyle(dark: model.tintIsDark, reduceMotion: model.reduceMotion))
                .disabled(waiting)
                .modifier(RobiPillArrival(index: index, shown: shown, reduceMotion: model.reduceMotion))
            }
            RobiMorePill(model: model, entries: moreEntries)
                .modifier(RobiPillArrival(index: leading, shown: shown, reduceMotion: model.reduceMotion))
        }
        .fixedSize()
    }

    /// The remaining actions, separated where their kind changes, then the overflowing questions.
    private var moreEntries: [RobiMoreMenu.Entry] {
        var entries: [RobiMoreMenu.Entry] = []
        var group: RobiIntent.Group?
        for intent in intents.dropFirst(leading) {
            if let group, group != intent.group { entries.append(.separator) }
            group = intent.group
            entries.append(.item(title: String(localized: intent.title), symbol: intent.symbol,
                                 isEnabled: !waiting, action: { [actions] in actions.suggest(intent) }))
        }
        if !moreQuestions.isEmpty {
            entries.append(.separator)
            entries.append(.header(String(localized: .robiSuggestedSection)))
            for question in moreQuestions {
                entries.append(.item(title: question, symbol: RobiIntent.suggested.symbol, isEnabled: true,
                                     action: { [actions] in actions.askSuggested(question) }))
            }
        }
        return entries
    }
}

/// "More" with a chevron, styled like the other pills, opening a native menu under itself.
private struct RobiMorePill: View {
    let model: RobiModel
    let entries: [RobiMoreMenu.Entry]
    @State private var anchor = RobiMenuAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            RobiMoreMenu.show(entries, under: view, dark: model.tintIsDark)
        } label: {
            HStack(spacing: 4) {
                Text(.robiSuggestMore)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .opacity(0.7)
            }
        }
        .buttonStyle(RobiPillStyle(dark: model.tintIsDark, reduceMotion: model.reduceMotion))
        .background(RobiMenuAnchorView(anchor: anchor))
        .accessibilityLabel(Text(.robiSuggestMoreLabel))
    }
}

/// Questions Apple Intelligence suggested for this context, each marked with sparkles. Clicking
/// one asks it like a typed question.
private struct RobiQuestionPills: View {
    let model: RobiModel
    let actions: RobiActions
    let questions: [String]
    /// Flips once the row is on screen, so the questions arrive the way the actions did.
    @State private var shown = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(questions.enumerated()), id: \.element) { index, question in
                Button { actions.askSuggested(question) } label: {
                    Label {
                        // The model's words, not app copy, so they are not looked up for translation.
                        Text(verbatim: question).lineLimit(1)
                    } icon: {
                        Image(systemName: RobiIntent.suggested.symbol).foregroundStyle(RobiQuestionPills.sparkle)
                    }
                }
                .buttonStyle(RobiPillStyle(dark: model.tintIsDark, reduceMotion: model.reduceMotion))
                .accessibilityHint(Text(.robiSuggestedHint))
                .modifier(RobiPillArrival(index: index, shown: shown, reduceMotion: model.reduceMotion))
            }
        }
        .fixedSize()
        .onAppear { shown = true }
    }

    /// Warm to cool, like Apple Intelligence's own colours; readable on light and dark pills.
    private static let sparkle = LinearGradient(
        colors: [Color(red: 1, green: 0.58, blue: 0.24), Color(red: 0.89, green: 0.34, blue: 0.72), Color(red: 0.42, green: 0.48, blue: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A pill growing in from just above its place, `index` steps behind the first. Reduce Motion
/// keeps only the fade.
private struct RobiPillArrival: ViewModifier {
    let index: Int
    let shown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.9, anchor: .top)
            .offset(y: shown || reduceMotion ? 0 : -4)
            .animation(RobiMotion.stagger(index, reduceMotion: reduceMotion), value: shown)
    }
}

extension RobiIntent {
    var title: LocalizedStringResource {
        switch self {
        case .explain: .robiSuggestExplain
        case .translate: .robiSuggestTranslate
        case .summarize: .robiSuggestSummarize
        case .doIt: .robiSuggestDoIt
        case .proofread: .robiSuggestProofread
        case .improve: .robiSuggestImprove
        case .shorten: .robiSuggestShorten
        case .formal: .robiSuggestFormal
        case .friendly: .robiSuggestFriendly
        case .reply: .robiSuggestReply
        case .actionItems: .robiSuggestActionItems
        case .suggested: .robiSuggestedSection
        case .custom: .robiPromptLabel
        }
    }

    var symbol: String {
        switch self {
        case .explain: "questionmark.bubble"
        case .translate: "character.bubble"
        case .summarize: "text.alignleft"
        case .doIt: "wand.and.stars"
        case .proofread: "text.badge.checkmark"
        case .improve: "pencil.line"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .formal: "briefcase"
        case .friendly: "face.smiling"
        case .reply: "arrowshape.turn.up.left"
        case .actionItems: "checklist"
        case .suggested: "sparkles"
        case .custom: "text.cursor"
        }
    }
}

#if DEBUG
/// The row on a stand-in title bar, as wide as Robi's panel.
private struct RobiSuggestionRowPreview: View {
    let model: RobiModel

    var body: some View {
        RobiSuggestionRow(model: model, actions: RobiActions())
            .padding(.vertical, 16)
            .frame(width: RobiMetrics.barWidth + 2 * RobiMetrics.sideMargin)
            .background(model.tintIsDark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(red: 0.86, green: 0.83, blue: 0.95))
    }
}

#Preview("Editable selection, light and dark") {
    VStack(spacing: 0) {
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.selection))
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, dark: true, context: RobiPreviewData.selection))
    }
}
#Preview("Window, light and dark") {
    VStack(spacing: 0) {
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.window))
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, dark: true, context: RobiPreviewData.window))
    }
}
#Preview("Suggested questions, light and dark") {
    VStack(spacing: 0) {
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.selection,
                                                              questions: RobiPreviewData.questions))
        RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, dark: true, context: RobiPreviewData.region,
                                                              questions: RobiPreviewData.questions))
    }
}
#Preview("German, suggested questions") {
    RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.selection,
                                                          questions: ["Klingt das zu förmlich?", "Kürzer für Slack"]))
        .environment(\.locale, Locale(identifier: "de"))
}
#Preview("Reading the window, Reduce Motion") {
    RobiSuggestionRowPreview(model: RobiPreviewData.model(.prompting, dark: true, context: RobiContext(kind: .window, text: ""),
                                                          reduceMotion: true, reading: true))
}
#endif
