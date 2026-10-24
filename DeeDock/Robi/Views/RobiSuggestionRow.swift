import SwiftUI

/// Explain, Translate, Summarize and Do It, hanging just below the prompt bar. The pills arrive
/// one after another, each a few hundredths of a second behind the last.
struct RobiSuggestionRow: View {
    let model: RobiModel
    let actions: RobiActions
    /// Flips on appearance so each pill can animate in from its hidden state.
    @State private var shown = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RobiIntent.suggestions.indices, id: \.self) { index in
                let intent = RobiIntent.suggestions[index]
                Button { actions.suggest(intent) } label: {
                    Label { Text(intent.title) } icon: { Image(systemName: intent.symbol) }
                }
                .buttonStyle(RobiPillStyle(dark: model.tintIsDark, reduceMotion: model.reduceMotion))
                .disabled(model.isReadingContext && model.context?.text.isEmpty != false)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown || model.reduceMotion ? 1 : 0.9, anchor: .top)
                .offset(y: shown || model.reduceMotion ? 0 : -4)
                .animation(RobiMotion.stagger(index, reduceMotion: model.reduceMotion), value: shown)
            }
        }
        .fixedSize()
        .onAppear { shown = true }
    }
}

extension RobiIntent {
    var title: LocalizedStringResource {
        switch self {
        case .explain: .robiSuggestExplain
        case .translate: .robiSuggestTranslate
        case .summarize: .robiSuggestSummarize
        case .doIt: .robiSuggestDoIt
        case .custom: .robiPromptLabel
        }
    }

    var symbol: String {
        switch self {
        case .explain: "questionmark.bubble"
        case .translate: "character.bubble"
        case .summarize: "text.alignleft"
        case .doIt: "wand.and.stars"
        case .custom: "text.cursor"
        }
    }
}

#if DEBUG
#Preview("Pills, light and dark") {
    VStack(spacing: 20) {
        RobiSuggestionRow(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.selection), actions: RobiActions())
            .padding(20)
            .background(Color(red: 0.86, green: 0.83, blue: 0.95))
        RobiSuggestionRow(model: RobiPreviewData.model(.prompting, dark: true, context: RobiPreviewData.region), actions: RobiActions())
            .padding(20)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }
}
#endif
