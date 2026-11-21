import SwiftUI

/// What sits above search results: example sentences while the field is empty, "✦ Understanding…"
/// while a sentence is read, then the understood tokens. Without a provider, nothing: plain name
/// search needs no explanation.
struct FlixSearchHead: View {
    let state: FlixPanelState

    var body: some View {
        if state.intelligence.searchesInPlainWords {
            if state.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                FlixAskSuggestions(examples: state.intelligence.searchExamples, run: state.runSearch)
                    .transition(FlixMotion.rise(reduceMotion: state.reduceMotion))
            } else {
                switch state.intelligence.query {
                case .idle:
                    EmptyView()
                case .understanding:
                    FlixUnderstanding(reduceMotion: state.reduceMotion)
                        .transition(.opacity)
                case .understood(let tokens, _):
                    FlixTokensBar(tokens: tokens, reduceMotion: state.reduceMotion, remove: state.intelligence.removeToken)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// "✦ Understanding…" over two shimmering rows.
private struct FlixUnderstanding: View {
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                FlixSparkle(size: 11)
                Text(.flixUnderstanding)
            }
            .font(.system(size: 11))
            .foregroundStyle(FlixStyle.faint)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            FlixLoadingRows(reduceMotion: reduceMotion)
                .accessibilityHidden(true)
        }
    }
}

/// "Ask in your own words" with example sentences.
struct FlixAskSuggestions: View {
    let examples: [String]
    let run: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.flixAskInYourOwnWords)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlixStyle.faint)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(examples, id: \.self) { example in
                Button { run(example) } label: {
                    HStack(spacing: 8) {
                        FlixSparkle(size: 11)
                        Text(verbatim: example)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(FlixSuggestionStyle())
                .accessibilityLabel(Text(verbatim: example))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }
}

/// A full-width suggestion row: a faint pane that lightens on hover.
private struct FlixSuggestionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        FlixHover { hovered in
            configuration.label
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(hovered ? FlixStyle.hover : FlixStyle.pane, in: shape)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(.rect)
                .contentShape(.focusEffect, shape)
        }
    }
}

#if DEBUG
#Preview("Search head: suggestions") {
    FlixAskSuggestions(examples: ["contract Mike sent last week", "screenshot with the build error", "photos from Berlin",
                                  "invoices over €1,000"], run: { _ in })
        .frame(width: 500)
}
#endif
