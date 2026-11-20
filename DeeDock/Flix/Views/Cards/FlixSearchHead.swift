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
            } else {
                switch state.intelligence.query {
                case .idle:
                    EmptyView()
                case .understanding:
                    HStack(spacing: 5) {
                        FlixSparkle(size: 11)
                        Text(.flixUnderstanding)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    FlixShimmer(reduceMotion: state.reduceMotion)
                    FlixShimmer(reduceMotion: state.reduceMotion).opacity(0.6)
                case .understood(let tokens, _):
                    FlixTokensBar(tokens: tokens, remove: state.intelligence.removeToken)
                }
            }
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
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            ForEach(examples, id: \.self) { example in
                Button { run(example) } label: {
                    HStack(spacing: 8) {
                        FlixSparkle(size: 11)
                        Text(verbatim: example)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(FlixStyle.pane, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }
}

/// "Understood as  [↓ Downloaded ✕] [Last 7 days ✕]".
struct FlixTokensBar: View {
    let tokens: [FlixQueryToken]
    let remove: (FlixQueryToken.ID) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(.flixUnderstoodAs)
            ForEach(tokens) { token in
                FlixTokenChip(label: token.label) { remove(token.id) }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// One removable token.
struct FlixTokenChip: View {
    let label: String
    var intelligent = false
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: label).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.flixRemoveToken(label)))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 22)
        .foregroundStyle(intelligent ? FlixStyle.aiViolet : Color.accentColor)
        .background(intelligent ? FlixStyle.aiSoft : Color.accentColor.opacity(0.2), in: .capsule)
        .fixedSize()
    }
}

/// "✦ Like IMG_4821.HEIC ✕  4 by meaning · Lookout".
struct FlixMoreLikeThisBar: View {
    let name: String
    let count: Int?
    let loading: Bool
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            FlixTokenChip(label: "✦ " + String(localized: .flixLikeToken(name)), intelligent: true, remove: clear)
            if loading { ProgressView().controlSize(.mini) }
            else if let count { Text(.flixMoreLikeThisCount(count)) }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
