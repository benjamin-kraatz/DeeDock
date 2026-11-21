import SwiftUI

/// Ask Robi about the selected files: suggested questions or your own, and the streamed answer.
///
/// The privacy line says exactly what leaves the Mac: the files you asked about, with your
/// question, to Claude with your key. Only reachable while Robi is ready (phase B2).
struct FlixAskRobiSheet: View {
    let state: FlixPanelState
    let items: [FlixItem]
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlixSheetTitle(title: Text(items.count == 1 ? .flixAskRobiAboutOne(items[0].name) : .flixAskRobiAboutMany(items.count))) {
            state.intelligence.resetRobi()
            state.sheet = nil
        }
        HStack(spacing: 6) {
            ForEach(Array(state.intelligence.robiQuestions(for: items).enumerated()), id: \.element) { index, suggestion in
                Button { ask(suggestion, suggestion: index) } label: { Text(verbatim: suggestion) }
                    .buttonStyle(.bordered)
                    .clipShape(.capsule)
            }
        }
        .controlSize(.small)
        TextField(text: $question) { Text(.flixAskRobiPlaceholder) }
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { ask(question, suggestion: nil) }
            .onAppear { focused = true }
        answer
        Label { Text(privacy) } icon: { Image(systemName: "lock.fill") }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
    }

    /// What leaves the Mac: the files, to Claude; or nothing, when Robi answers on this Mac.
    private var privacy: LocalizedStringResource {
        if state.intelligence.robiAnswersOnDevice { return .flixAskRobiPrivacyOnDevice }
        return items.count == 1 ? .flixAskRobiPrivacyOne : .flixAskRobiPrivacyMany
    }

    @ViewBuilder private var answer: some View {
        switch state.intelligence.robi {
        case .idle:
            EmptyView()
        case .answering(_, let text), .answered(_, let text):
            Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.1), value: text)
        case .failed(_, let message):
            Text(verbatim: message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    /// - Parameter suggestion: The suggested question's position, nil for a typed one.
    private func ask(_ text: String, suggestion: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.ask(trimmed, about: items, suggestionIndex: suggestion)
    }
}
