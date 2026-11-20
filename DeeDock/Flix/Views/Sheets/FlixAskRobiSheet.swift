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
            ForEach(state.intelligence.robiQuestions(for: items), id: \.self) { suggestion in
                Button { ask(suggestion) } label: { Text(verbatim: suggestion) }
                    .buttonStyle(.bordered)
                    .clipShape(.capsule)
            }
        }
        .controlSize(.small)
        TextField(text: $question) { Text(.flixAskRobiPlaceholder) }
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { ask(question) }
            .onAppear { focused = true }
        answer
        Label { Text(items.count == 1 ? .flixAskRobiPrivacyOne : .flixAskRobiPrivacyMany) } icon: { Image(systemName: "lock.fill") }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
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

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.intelligence.ask(trimmed, about: items)
    }
}
