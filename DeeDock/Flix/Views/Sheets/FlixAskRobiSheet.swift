import SwiftUI

/// Ask Robi about the selected files: suggested questions or your own, and the streamed answer.
///
/// The privacy line says exactly what leaves the Mac: the files you asked about, with your
/// question, to Claude with your key. Only reachable while Robi is ready (phase B2). While the
/// answer streams a violet caret blinks at its end; with Reduce Motion the caret is steady.
struct FlixAskRobiSheet: View {
    let state: FlixPanelState
    let items: [FlixItem]
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlixSheetTitle(title: Text(items.count == 1 ? .flixAskRobiAboutOne(items[0].name) : .flixAskRobiAboutMany(items.count)),
                       mark: .robi) {
            state.intelligence.resetRobi()
            state.sheet = nil
        }
        // Questions wrap onto further lines; long ones (German) truncate inside their chip.
        FlixFlow {
            ForEach(Array(state.intelligence.robiQuestions(for: items).enumerated()), id: \.element) { index, suggestion in
                Button { ask(suggestion, suggestion: index) } label: { Text(verbatim: suggestion) }
                    .buttonStyle(FlixChipButtonStyle())
            }
        }
        FlixSheetField(text: $question, prompt: Text(.flixAskRobiPlaceholder), focus: $focused) {
            ask(question, suggestion: nil)
        }
        .onAppear { focused = true }
        FlixRobiAnswer(answer: state.intelligence.robi, reduceMotion: state.reduceMotion)
        Label { Text(privacy).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "lock.fill") }
            .font(.system(size: 10.5))
            .foregroundStyle(FlixStyle.faint)
            .accessibilityElement(children: .combine)
    }

    /// What leaves the Mac: the files, to Claude; or nothing, when Robi answers on this Mac.
    private var privacy: LocalizedStringResource {
        if state.intelligence.robiAnswersOnDevice { return .flixAskRobiPrivacyOnDevice }
        return items.count == 1 ? .flixAskRobiPrivacyOne : .flixAskRobiPrivacyMany
    }

    /// - Parameter suggestion: The suggested question's position, nil for a typed one.
    private func ask(_ text: String, suggestion: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.ask(trimmed, about: items, suggestionIndex: suggestion)
    }
}

/// Robi's mark: a white R on the intelligence gradient, as in the mockup.
struct FlixRobiBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: [FlixStyle.aiViolet, FlixStyle.aiBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 22, height: 22)
            .overlay { Text(verbatim: "R").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white) }
            .accessibilityHidden(true)
    }
}

/// The answer as it streams, then complete; or why there is none.
private struct FlixRobiAnswer: View {
    let answer: FlixRobiAnswerState
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch answer {
            case .idle:
                EmptyView()
            case .answering(_, let text):
                if text.isEmpty {
                    FlixCaret(reduceMotion: reduceMotion)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                } else {
                    answerText(text, streaming: true)
                }
            case .answered(_, let text):
                answerText(text, streaming: false)
            case .failed(_, let message):
                FlixSheetNote(text: Text(verbatim: message))
            }
        }
        .transition(.opacity)
    }

    private func answerText(_ text: String, streaming: Bool) -> some View {
        var answer = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        if streaming {
            // The caret trails the text inline, so it wraps with the last word. One attributed
            // string, not an interpolated `Text`, which would make Robi's answer a localization key.
            var caret = AttributedString(" ▍")
            caret.foregroundColor = FlixStyle.aiViolet
            answer += caret
        }
        return ScrollView {
            Text(answer)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 180)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: text)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The violet caret shown while Robi has not said anything yet. Blinks once a second; steady with Reduce
/// Motion.
private struct FlixCaret: View {
    let reduceMotion: Bool
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(FlixStyle.aiViolet)
            .frame(width: 7, height: 13)
            .opacity(dim ? 0.15 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Ask Robi") {
    FlixPanelView(state: FlixPreviewData.panelState(.askRobi)).frame(width: 760, height: 608)
}

#Preview("Ask Robi, answering, German") {
    FlixPanelView(state: FlixPreviewData.panelState(.askRobiAnswering)).frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Ask Robi, failed, on this Mac") {
    FlixPanelView(state: FlixPreviewData.panelState(.askRobiFailed)).frame(width: 760, height: 608)
}
#endif
